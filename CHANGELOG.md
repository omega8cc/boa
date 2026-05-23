# Changelog — [PROJECT NAME]

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html) where applicable,
otherwise date-stamped entries for non-versioned work.

---

## [Unreleased]

### Added
- `aegir/conf/tpl/maintenance.html` — generic 503 maintenance template,
  deployed to `/var/www/nginx-default/maintenance.html` by `_nginx_mime_check_fix`.
- HTTP-off migration short-circuit in both `aegir/conf/global/global.inc`
  (legacy single-file) and `aegir/conf/global/global-mode.inc` (modern
  shared): presence of `/data/disk/<oct>/static/control/http-off.pid` makes
  every site on the account return 503 with `Retry-After`, `X-Accel-Expires`
  (Nginx microcache), and `Cache-Control` headers. TTL is read from the pid
  file contents (default 300s, clamped 30..86400).

### Changed
- `xboa` export step now creates the per-account `http-off.pid` (default
  3600s TTL) and purges `/var/lib/nginx/speed` so already-cached 200
  responses on hot URLs (homepages especially) cannot mask the 503.
- `xboa` proxy step removes `http-off.pid` after Nginx reload and purges
  the speed cache again before writing `proxied.pid`, so cached 503s do
  not linger after the proxy vhost takes over.

### Fixed
- Migration data-consistency on Drupal 8+ sites and on busy commerce/API
  sites where `readonlymode` is unavailable via system drush 8 or bypassed
  by application code paths.
- security: `daily.sh` no longer follows attacker-controlled symlinks
  during the per-site chown sweep. `chown -L -R` (which explicitly
  dereferenced links during recursion) replaced with `chown -h -R`
  at lines 1725/1738/1745, and a `_validate_safe_dir` helper now
  realpath-canonicalises the alias-derived `_Dir`/`_Plr` paths and
  skips the loop iteration unless they resolve under `/data/disk/`,
  `/var/aegir/`, or `/home/`.
- security: `/var/tmp/fpm` (PHP-FPM opcache lockfile path) created
  with mode 1777 (sticky) instead of 0777. Prevents cross-tenant
  deletion of opcache lockfiles between PHP-FPM pools running as
  different per-tenant uids.
- security: `/var/log/php*` set to mode 0755 root:adm instead of 0777.
  Cross-tenant pool-name enumeration and arbitrary-file creation in
  the log directory are now blocked; PHP-FPM workers still append to
  pool logs via the master's inherited fd.
- security: `/opt/tmp` (BOA scratch root) created with mode 1777
  (sticky) instead of `chmod -R 777`. Matches the sticky-scratch model
  already used for `/var/tmp/fpm` and `/opt/user/{gems,npm}`. The
  explicit `find /opt/tmp/boa -exec chmod` calls still set the boa
  subtree to 0755/0644; other subtrees keep their existing modes
  rather than being blanket-rewritten on every install/upgrade.
- security: `/data/conf/arch/log` set to mode 0755 instead of 0777
  in both `system.sh.inc` and `satellite.sh.inc`. The directory is
  vestigial (no writer in the current codebase); tightening prevents
  any future feature from inheriting a wide-open creator surface.
- security: `scan_nginx.sh` strips non-printable characters from the
  DDoS-UA fingerprint before echo and verbose-log emission. Prevents an
  attacker-controlled User-Agent from injecting terminal escape sequences
  into cron stdout / `tail -f` views; no behavioural change for legitimate
  UAs.
- security: `scan_nginx.sh` per-line IP candidate filter now calls
  `_validate_ip` (which adds the per-octet 0..255 range check) instead of
  the loose regex `^([0-9]{1,3}\.){3}[0-9]{1,3}$`. Off-spec strings such
  as `999.999.999.999` no longer enter the UA-tracking and path-flood
  associative arrays. csf already rejected them downstream — this just
  filters earlier.
- security: NOPASSWD-sudo helpers harden against caller-planted symlinks.
  `aegir/tools/bin/fix-drupal-{platform,site}-{ownership,permissions}.sh`
  and `aegir/tools/bin/lock-local-drush-permissions.sh` now validate
  `--root`/`--site-path` resolves under `/var/aegir/`, `/data/disk/`, or
  `/home/`; `chown -L -R` replaced with `chown -h -R`; every direct
  `chmod` routed through a wrapper that skips symlinks. Closes the
  tar-archive-with-symlink → aegir → root escalation path.

### Removed
- `xboa`: drush8 `en readonlymode -y` call in the per-site export step and
  the long-commented-out `dis readonlymode` block in the per-site import
  step. The PHP-level http-off mechanism supersedes both.

---

<!-- Add versioned or dated releases below, newest first -->

## [0.1.0] — YYYY-MM-DD

### Added
- Initial project structure
- CLAUDE.md, DECISIONS.md, CHANGELOG.md
