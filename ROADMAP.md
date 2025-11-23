# BOA Roadmap & Progress

Documenting ongoing, upcoming and completed tasks, organized alphabetically.

Some tasks are relatively simple, while others are major undertakings that take weeks or months. Therefore, we are working on many things simultaneously.

This document highlights the most complex or important tasks we are working on or planning to undertake. Routine tasks such as debugging, fixing issues, and implementing small improvements are usually documented in the commit history and changelog, which are updated with each new BOA release.

Certain planned features are likely to be exclusive to **BOA PRO**, as indicated below:

## RELEASED IN BOA PRO

- **Amazon S3 Alternatives**: Integrate support for AWS S3 eight (8) alternatives in `multiback` and `mybackup` (PRO)

## RELEASED IN BOA LTS/PRO

- **Drupal 11 with Aegir 3**: They Said It Couldn’t Be Done — We Did It Anyway (PRO/LTS)
- **Solr 9 Support**: Add latest Solr Server 9 as supported via BOA automation (PRO/LTS)
- **PHP 8.4 Support**: Enhancing performance and supporting eleven PHP versions (PRO/LTS)
- **Ægir Task for SQL Backup**: Enable classic mysqldump backups for individual site downloads (PRO/LTS)
- **Debian Bookworm and Devuan Daedalus**: Ensure compatibility for installation and automated upgrades (PRO/LTS)
- **Drush 12/13 in Aegir Tasks**: Dynamically Utilize Site-Local Drush for `updatedb` Operations on Drupal 10+ (PRO/LTS)
- **Percona for MySQL 8.0**: Add support for Percona Server 8.0, necessary for Drupal 11 (PRO/LTS)
- **PHP 8.3 Support**: Required for Drupal 11, enhancing performance and supporting ten PHP versions (PRO/LTS)
- **Ruby Gems and Node/NPM Support 3x Faster**: From 15 to 5 minutes, with improved security (PRO/LTS)
- **Super Fast System AutoInit**: Facilitate easy upgrades to the latest Devuan before BOA installation (PRO/LTS)
- **Use OpenSSL 3**: Maintain compatibility with OpenSSL 1.1.1 for legacy PHP versions (PRO/LTS)

## IN PROGRESS

- **PHP 8.5 Support**: Enhancing performance and supporting twelve PHP versions (PRO/LTS)
- **Backdrop CMS Support**: Implement Backdrop CMS as a supported platform (PRO/LTS)
- **Grav CMS Support**: Introduce support for Grav CMS (command line only) (PRO/LTS)
- **Import from Classic Ægir**: Extend xboa to import from remote classic Ægir servers using Nginx or Apache (PRO/LTS)
- **Optional AppArmor Support**: Enhanced security and accounts privilege separation (PRO)
- **Symlink Site Files**: Automatically symlink all site files to expedite migration tasks and conserve disk space (PRO)
- **Tar Pipelines on Clone**: Use Tar Pipelines to create separate symlinked copies during site clone tasks (PRO)

## UPCOMING TASKS

- **Ægir Admin Interface**: Transition the Ægir admin interface to Backdrop CMS (PRO/LTS)
- **BO4D**: Offer a *BOA For Docker* version tailored for local development (PRO/LTS)
- **DDEV Integration**: Add support for BOA-compatible configurations within DDEV (PRO/LTS)
- **Documentation Consolidation**: Consolidate all legacy and built-in documentation into a unified Grav CMS site.

## COMPLETED IN BOA DEV

- **Documentation Conversion to Markdown**: Update all BOA documentation from legacy TXT to Markdown.
