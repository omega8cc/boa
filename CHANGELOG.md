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
  3600s TTL) and bumps `speed_booster_anon_cache_ttl=3600` in each site's
  `boa_site_control.ini` as a defensive belt-and-braces measure.
- `xboa` proxy step removes `http-off.pid` after Nginx reload, before
  writing `proxied.pid`.

### Fixed
- Migration data-consistency on Drupal 8+ sites and on busy commerce/API
  sites where `readonlymode` is unavailable via system drush 8 or bypassed
  by application code paths.

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
