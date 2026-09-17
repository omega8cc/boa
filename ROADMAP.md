# BOA Roadmap & Progress

Documenting ongoing, upcoming and completed tasks. Some tasks are relatively simple, while others are major undertakings that take weeks or months. Therefore, we are working on many things simultaneously.

This document highlights the most complex or important tasks we are working on or planning to undertake. Routine tasks such as debugging, fixing issues, and implementing small improvements are usually documented in the commit history and changelog, which are updated with each new BOA release.

All features ship to both **LTS** and **PRO** — the branches are kept **1:1**. The only exception is the **extended backup sub-system** (see RELEASED IN BOA PRO only), the sole feature requiring a **BOA PRO** license subscription — designed as something extra for those who decided to support BOA.

Please also note that the LTS branch is **kept up to date alongside PRO**: frequent security updates and serious new-feature work are ongoing — and the free branch receives them.

## IN PROGRESS

- **Ægir Admin Interface**: Transition the Ægir admin interface to Backdrop CMS

## RELEASED IN BOA PRO only

- **Amazon S3 Alternatives**: Integrate support for AWS S3 eight (8) alternatives in `multiback` and `mybackup`

## MAJOR NEW FEATURES RELEASED IN BOA LTS/PRO

- **Grav CMS Support**: Grav 2 sites under the Ægir control panel — opt-in, self-updating platforms, per-site full installs, the `grav` CLI, mirror-fed one-click upgrades
- **Textpattern CMS Support**: Textpattern sites under the Ægir control panel — opt-in, shared-core multisite platforms tracking the newest official release, enforced modern PHP
- **Replication Standby You Can Trust**: A passive mirror whose database refuses every local write (`super_read_only`, held across restarts and reboots), whose web tier stays down until promotion, and whose files keep themselves current
- **boa-restore**: Open your encrypted off-site backups on your own workstation with no BOA server involved — `check`, `list` and `restore` into fresh folders, never writing to your bucket
- **Migration Source Task**: Point Drupal's migration tooling at another of your sites in one control-panel task — no new secret written, SELECT on exactly one database, revoked when unset
- **Restorable, Verified Backups**: Every backup the panel, the API, a bulk action or a schedule takes is the self-contained restorable kind, and a failed or truncated export fails the backup instead of archiving nothing
- **Optional AppArmor Support**: 46 confinement profiles for PHP and its daemons — off by default, opt-in via a control file, in complain or enforce mode
- **XDR9000 Permanent Archive**: An append-only, upgrade-proof archive every box keeps about itself — bans, self-heals, backup outcomes, metrics — readable with one root command
- **Drupal 11 Database Gate**: Drupal 11 needs Percona 8.4 — on a Percona 5.7 server the platform builder skips Drupal 11 with a note and a Drupal 11 site install stops with one reason, instead of failing deep inside the installer
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

- **A Task Queue That Heals Itself**: A task whose runner died is reaped by the dispatcher and by an outside watchdog, marked failed with a truthful log entry, never re-run
- **Root Keeps Its Boundary**: A hardening sweep so that no root file operation follows a symlink planted at a name BOA maintains
- **Faster Clone and Migrate**: FastTrack skips the pre-flight verifications and MyQuick copies the database in parallel per table; a clone's files land in its own symlinked store rather than being copied
- **xtrim**: Retire a fully proxied migration source in stages, from a dry plan through a reversible quiesce to the one-way shrink, removing nothing until the migration is proven complete
- **Distributed Scraper Detection**: Cold interactive-only fetches are answered with a static 404 before PHP is reached, with a campaign-level IDS detector (report-only by default)
- **Site Operator Role and Task Provenance**: A control-panel role for day-to-day site tasks without Backup, Restore, Reset password or Delete, and every task records which login queued it
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
