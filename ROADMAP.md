# Planned BOA Features, Improvements, and TODO List

Documenting details in progress...

## New Features

- **Backdrop CMS Support (Urgent)**: Add support for Backdrop CMS as a platform.
- **Grav CMS Support**: Add support for Grav CMS (command line only).
- **Symlink Site Files**: Automatically symlink all site files to speed up migration tasks and save disk space.
- **Rsync on Clone**: Use Rsync to create separate symlinked copies during site clone tasks.
- **Automate Mass Import**: Extend xboa tool features to automate mass import procedures from remote classic Ægir servers running Nginx or Apache.
- **Percona Server for MySQL 8.0**: Test and support migration to Percona Server for MySQL 8.0, as Percona/MySQL 5.7 reached EOL in October 2023.
- **Amazon S3 Alternatives**: Add support for Amazon S3 alternatives to backboa and duobackboa.
- **Ægir Remote Servers**: Implement the Ægir Remote Servers feature to meet user needs.

## Improvements

- **Documentation Consolidation**: Update and consolidate all legacy and built-in documentation into a single Grav CMS and Git-based site for a unified point of reference.

## Changes and Upgrades

- **Ægir Admin Interface (Urgent)**: Switch the Ægir admin interface from Drupal 7 to Backdrop CMS.
- **Configurable Site Backups**: Modify Ægir site backups to exclude all files and database dumps by default, making it configurable with new control files to preserve Restore task functionality if desired by the user.

## Important Fixes

- **Drush Support**: Ensure Drush 11/12 support with Redispatch to site-local Drush (vdrush, sdrush).
