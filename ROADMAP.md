# Planned BOA Features, Improvements, and TODO List

Documenting details in progress...

## New Features

- **Debian Bookworm and Devuan Daedalus**: Add compatibility for installation and automated upgrades (DONE).
- **Super Fast System AutoInit**: Upgrade easily to the latest Devuan before installing BOA (DONE).
- **PHP 8.3 Support**: Required by Drupal 11 and much faster, bringing the total PHP versions to 10 (DONE).
- **Percona for MySQL 8.0**: Add support for Percona Server 8.0 (required by Drupal 11).
- **Import from Classic Ægir**: Extend xboa to import from remote classic Ægir servers running Nginx or Apache.
- **Ægir Task for SQL Backup**: Make it possible to create classic mysqldump backups for download per site.
- **Symlink Site Files**: Automatically symlink all site files to speed up migration tasks and save disk space.
- **Rsync on Clone**: Use Rsync to create separate symlinked copies during site clone tasks.
- **Backdrop CMS Support**: Add support for Backdrop CMS as a platform.
- **Grav CMS Support**: Add support for Grav CMS (command line only).
- **Amazon S3 Alternatives**: Add support for Amazon S3 alternatives to backboa and duobackboa.
- **Ægir Remote Servers**: Implement the Ægir Remote Servers feature to meet user needs.

## Improvements

- **Documentation Conversion to Markdown**: All BOA docs should be updated from legacy TXT to Markdown (DONE)
- **Documentation Consolidation**: Update all legacy and built-in documentation into a single Grav CMS site.

## Changes and Upgrades

- **Use OpenSSL LTS 3.0**: But keep 1.1.1 to support legacy PHP versions (DONE).
- **Ægir Admin Interface**: Switch the Ægir admin interface from Drupal 7 to Backdrop CMS.

## Important Fixes

- **Drush Support**: Ensure Drush 11/12 support with Redispatch to site-local Drush (vdrush, sdrush).
