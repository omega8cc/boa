# BOA Roadmap & Progress

Documenting ongoing, upcoming and completed tasks. Some tasks are relatively simple, while others are major undertakings that take weeks or months. Therefore, we are working on many things simultaneously.

This document highlights the most complex or important tasks we are working on or planning to undertake. Routine tasks such as debugging, fixing issues, and implementing small improvements are usually documented in the commit history and changelog, which are updated with each new BOA release.

All features ship to both **LTS** and **PRO** — the branches are kept **1:1**. The only exception is the **extended backup sub-system** (see RELEASED IN BOA PRO only), the sole feature requiring a **BOA PRO** license subscription — designed as something extra for those who decided to support BOA.

Please also note that the LTS branch is **kept up to date alongside PRO**: frequent security updates and serious new-feature work are ongoing — and the free branch receives them.

## IN PROGRESS

- **Grav CMS Support**: Introduce support for Grav CMS (command line only)
- **Optional AppArmor Support**: Enhanced security and accounts privilege separation
- **Tar Pipelines on Clone**: Use Tar Pipelines to create separate symlinked copies during site clone tasks
- **Ægir Admin Interface**: Transition the Ægir admin interface to Backdrop CMS

## RELEASED IN BOA PRO only

- **Amazon S3 Alternatives**: Integrate support for AWS S3 eight (8) alternatives in `multiback` and `mybackup`

## MAJOR NEW FEATURES RELEASED IN BOA LTS/PRO

- **Documentation Consolidation**: Convert legacy and built-in docs into a unified Grav CMS site
- **Backdrop CMS Support**: First-class platform — site lifecycle, bee CLI, safe Drupal 7 upgrades
- **Import from Classic Ægir**: Import from remote Ægir servers (Nginx or Apache) with per-site revert
- **HTTP/3 on QUIC with KTLS Magic**: Strap in, your sites are getting an F1 engine
- **Drupal 11 with Ægir 3**: They Said It Couldn’t Be Done — We Did It Anyway
- **Debian Trixie and Devuan Excalibur**: Ensure compatibility for installation and automated upgrades
- **Debian Bookworm and Devuan Daedalus**: Ensure compatibility for installation and automated upgrades
- **Percona for MySQL 8.4**: Add support for Percona Server 8.4, the new Percona LTS
- **Original MySQL 8.4**: Add support for original MySQL Server 8.4 on Trixie/Excalibur
- **Percona for MySQL 8.0**: Add support for Percona Server 8.0, necessary for Drupal 11
- **Super Fast System AutoInit**: Facilitate easy upgrades to the latest Devuan before BOA installation
- **Use OpenSSL 3 by default**: Maintain compatibility with OpenSSL 1.1.1 for legacy PHP versions

## OTHER NEW FEATURES RELEASED IN BOA LTS/PRO

- **BOA Local**: Install and run BOA locally without a public IP or DNS, for development and testing
- **DDEV Integration**: Pull a BOA-hosted site's database and files into a local DDEV project with the `ddev-boa` add-on
- **PHP 8.5 Support**: Enhancing performance and supporting twelve PHP versions
- **PHP 8.4 Support**: Enhancing performance and supporting eleven PHP versions
- **PHP 8.3 Support**: Required for Drupal 11, enhancing performance and supporting ten PHP versions
- **Add instant SQL fallback for Valkey/Redis**: zero downtime during upgrades/restarts/etc
- **Symlink Site Files**: Automatically symlink all site files to expedite migration tasks and conserve disk space
- **Solr 9 Support**: Add latest Solr Server 9 as supported via BOA automation
- **Ruby Gems and Node/NPM Support 3x Faster**: From 15 to 5 minutes, with improved security
- **Ægir Task for SQL Backup**: Enable classic mysqldump backups for individual site downloads
- **Drush 12/13 in Ægir Tasks**: Dynamically Utilize Site-Local Drush for `updatedb` Operations on Drupal 10+
- **Documentation Conversion to Markdown**: Update all BOA documentation from legacy TXT to Markdown.
