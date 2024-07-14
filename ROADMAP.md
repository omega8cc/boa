# BOA Roadmap & Progress

Documenting ongoing, upcoming and completed tasks, organized alphabetically.

Some tasks are relatively simple, while others are major undertakings that take weeks or months. Therefore, we are working on many things simultaneously.

This document highlights the most complex or important tasks we are working on or planning to undertake. Routine tasks such as debugging, fixing issues, and implementing small improvements are usually documented in the commit history and changelog, which are updated with each new BOA release.

## IN PROGRESS
- **Ægir Task for SQL Backup**: Enable classic mysqldump backups for individual site downloads.
- **Drush Support**: Ensure compatibility with Drush 11/12, including Redispatch to site-local Drush (vdrush).
- **Import from Classic Ægir**: Extend xboa to import from remote classic Ægir servers using Nginx or Apache.
- **Percona for MySQL 8.0**: Add support for Percona Server 8.0, necessary for Drupal 11.
- **Rsync on Clone**: Use Rsync to create separate symlinked copies during site clone tasks.
- **Symlink Site Files**: Automatically symlink all site files to expedite migration tasks and conserve disk space.

## UPCOMING TASKS
- **Ægir Admin Interface**: Transition the Ægir admin interface from Drupal 7 to Backdrop CMS.
- **Ægir Remote Servers**: Implement the Ægir Remote Servers feature to address user requirements.
- **Amazon S3 Alternatives**: Integrate support for Amazon S3 alternatives in backboa and duobackboa.
- **Backdrop CMS Support**: Implement Backdrop CMS as a supported platform.
- **BO4D**: Offer a *BOA On Docker* version tailored for local development, incorporating the features of *DDEV*.
- **DDEV Integration**: Add support for BOA-compatible configurations within DDEV.
- **Documentation Consolidation**: Consolidate all legacy and built-in documentation into a unified Grav CMS site.
- **Grav CMS Support**: Introduce support for Grav CMS (command line only).

## COMPLETED IN BOA-DEV
- **Debian Bookworm and Devuan Daedalus**: Ensure compatibility for installation and automated upgrades.
- **Documentation Conversion to Markdown**: Update all BOA documentation from legacy TXT to Markdown.
- **PHP 8.3 Support**: Required for Drupal 11, enhancing performance and supporting ten PHP versions.
- **Super Fast System AutoInit**: Facilitate easy upgrades to the latest Devuan before BOA installation.
- **Use OpenSSL LTS 3.0**: Maintain compatibility with OpenSSL 1.1.1 for legacy PHP versions.

