# Welcome to BOA!

BOA stands for Barracuda, Octopus, and Ægir—a high-performance LEMP stack supporting Drupal from Pressflow 6 to the latest Drupal 11, as well as Backdrop CMS and Grav CMS (soon).

## What is Ægir?

Ægir, named after the Norse god of the sea, is an open-source hosting system for managing multiple Drupal sites. The name Ægir was chosen to reflect the relationship between Drupal's water drop logo, symbolizing individual sites, and Ægir's role as the god of the ocean, representing the hosting of many Drupal sites together. It automates tasks such as site installation, upgrades, and maintenance, making your life easier.

**Announcement from Omega8.cc team**: [**The Future of Aegir 3 is Bryght!**](https://github.com/omega8cc/boa/tree/5.x-pro/ANNOUNCEMENT.md)

### Key Features of Ægir:

- **Site Management**: Manage multiple Drupal sites from a single interface.
- **Automation**: Automate code deployment, database updates, and site backups.
- **Scalability**: Easily scale your Drupal hosting infrastructure.
- **Multitenancy**: Share a codebase across multiple sites with separate databases.
- **Open-Source**: Customize and extend Ægir to fit your needs.
- **Integration with Drush**: Use powerful command-line tools for site administration.

<img width="1215" height="1264" alt="Aegir-BOA" src="https://github.com/user-attachments/assets/b2417cc7-2fb8-422c-96f8-71d12c1c2fd7" />

## Why Barracuda?

Barracuda is a specially tuned hosting environment for Ægir, designed to be lightning fast and agile, just like the barracuda fish known for its incredible speed and agility in the ocean.

## Why Octopus?

Octopus is a smart system designed to manage multiple Ægir instances within Barracuda. Just like the sea creature with eight limbs, Octopus allows you to create and manage many separate but connected Ægir instances, showcasing its intelligence and adaptability in efficiently handling complex hosting environments.

## Dual License

**BOA** remains a **Free/Libre Open Source Project**. While all of **BOA** code is **Free/Libre Open Source**, only the **BOA LTS** branch and **Ægir** are available without any cost or restrictions.

Check out the details in [DUALLICENSE.md](https://github.com/omega8cc/boa/tree/5.x-pro/DUALLICENSE.md).

## BOA Priorities

- **High Performance**: Ensure your sites run fast.
- **Security**: Keep your sites and system secure.
- **Automation**: Minimize daily maintenance with automated system and OS upgrades.

## Multi-Ægir Hosting

Leverage one Ægir Master Instance and multiple Satellite Instances. Use Satellite Instances to host your sites, as the Master holds the central Nginx configuration. Note: The 'Master' and 'Satellite' names in the Barracuda/Octopus context are not related to the multi-server Ægir features but to the multi-instance environment with virtual chroot/jail for each Ægir Satellite instance.

## Installation Scripts

- **BOA**: Runs Barracuda and Octopus to install complete BOA system.
- **BARRACUDA**: Upgrades the system and the Ægir Master Instance.
- **OCTOPUS**: Updates Ægir Instances + Drupal platforms.

## Bug Reporting

Follow the guidelines in [docs/CONTRIBUTING.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/CONTRIBUTING.md).

## Requirements

- Basic sysadmin skills and experience.
- Willingness to accept BOA PI (paranoid idiosyncrasies).
- Minimum 4 GB RAM and 2 CPUs (8 GB RAM and 4+ CPUs with Solr).
- SSH (RSA) keys for root are required by newer OpenSSH versions used in BOA.
- Wget must be installed.
- Open outgoing TCP ports: 25, 53, 80, 443.
- Locales with UTF-8 support, otherwise en_US.UTF-8 (default) is forced.

## Provided Services and Features

Check out the details in [docs/PROVIDES.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/PROVIDES.md).

## Supported Virtualization Systems

- LXC
- KVM
- VServer
- Hyper-V
- OpenVZ
- Parallels
- VirtualBox
- VMware ESXi
- Xen

## Supported Operating Systems

### Devuan (recommended)

- Excalibur (supported, but only with MySQL 8.4)
- Daedalus (default, with Percona 5.7, 8.0 or 8.4)
- Chimaera (supported but upgrade recommended)
- Beowulf (supported for upgrades)

### Debian (for migration)

- Trixie (supported only as a base for migration to Devuan)
- Bookworm (supported only as a base for migration to Devuan)
- Bullseye (supported only as a base for migration to Devuan)
- Buster (supported only as a base for migration to Devuan)
- Stretch (deprecated but still works, please upgrade to Chimaera)
- Jessie (deprecated but still works, please upgrade to Chimaera)

## Project Roadmap

Check out the details in [ROADMAP](https://github.com/omega8cc/boa/tree/5.x-pro/ROADMAP.md)

## Documentation and Templates

- Installation Instructions: [docs/INSTALL.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/INSTALL.md)
- Upgrade Instructions: [docs/UPGRADE.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/UPGRADE.md)
- Major-Upgrade Instructions: [docs/MAJORUPGRADE.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/MAJORUPGRADE.md)
- Importance of Keeping SKYNET Enabled in BOA: [docs/SKYNET.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/SKYNET.md)
- INI configuration per site: [docs/ini/site/INI.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/ini/site/INI.md)
- INI configuration per platform: [docs/ini/platform/INI.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/ini/platform/INI.md)
- Configuration Templates: [docs/cnf/barracuda.cnf](https://github.com/omega8cc/boa/tree/5.x-pro/docs/cnf/barracuda.cnf), [docs/cnf/octopus.cnf](https://github.com/omega8cc/boa/tree/5.x-pro/docs/cnf/octopus.cnf)
- System Control Files Index: [docs/ctrl/system.ctrl](https://github.com/omega8cc/boa/tree/5.x-pro/docs/ctrl/system.ctrl)

## Documentation for BOA PRO

- New Backups for BOA SysAdmin [docs/BACKUP_ROOT.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/BACKUP_ROOT.md)
- New Backups for Octopus Lshell User [docs/BACKUP_USER.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/BACKUP_USER.md)
- New Backups Retention Policy Configuration [docs/BACKUP_RETENTION.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/BACKUP_RETENTION.md)
- Supported Regions and Bucket Creation Guidelines [docs/BACKUP_REGIONS.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/BACKUP_REGIONS.md)

## Additional Documentation

- Composer How-To: [docs/COMPOSER.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/COMPOSER.md)
- Dev-Mode Notes: [docs/DEVELOPMENT.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/DEVELOPMENT.md)
- Drupal Contrib Modules: [docs/MODULES.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/MODULES.md)
- Extra Comments: [docs/CAVEATS.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/CAVEATS.md)
- FAQ: [docs/FAQ.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/FAQ.md)
- Fast DB Operations: [docs/MYQUICK.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/MYQUICK.md)
- Fast Migrate/Clone: [docs/FASTTRACK.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/FASTTRACK.md)
- Included Platforms: [docs/PLATFORMS.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/PLATFORMS.md)
- Let’s Encrypt: [docs/SSL.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/SSL.md)
- Migration (Octopus Instance): [docs/MIGRATE.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/MIGRATE.md)
- Migration (Single Site): [docs/REMOTE.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/REMOTE.md)
- New Relic How-To: [docs/NEWRELIC.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/NEWRELIC.md)
- Nginx Custom Rewrites: [docs/REWRITES.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/REWRITES.md)
- PHP-CLI and Drush Configuration How-To: [docs/DRUSH-CLI.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/DRUSH-CLI.md)
- PHP-FPM Configuration How-To: [docs/PHP-FPM.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/PHP-FPM.md)
- Remote S3 Backups: [docs/BACKUPS.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/BACKUPS.md)
- Ruby Gems and NPM: [docs/GEM.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/GEM.md)
- Security Settings: [docs/SECURITY.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/SECURITY.md)
- Self-Upgrade How-To: [docs/SELFUPGRADE.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/SELFUPGRADE.md)
- SMTP SSL Error Debugging: [docs/SMTP_SSL_DEBUG.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/SMTP_SSL_DEBUG.md)
- Solr and Jetty How-To: [docs/SOLR.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/SOLR.md)
- SSH Encryption: [docs/BLOWFISH.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/BLOWFISH.md)
- VServer Cluster: [docs/CLUSTER.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/CLUSTER.md) (deprecated)

## Useful Links

- BOA User Handbook (legacy): [Learn BOA](https://learn.omega8.cc/library/good-to-know)
- Ægir Docs (legacy): [Ægir Project](https://docs.aegirproject.org)

## Maintainers

BOA is maintained by [Omega8.cc](https://omega8.cc/about).

## Credits

Thanks to the Ægir Project founders and developers. [Ægir Team](https://docs.aegirproject.org/community/core-team/).

## Support

Support BOA development by purchasing a commercial license or using Omega8.cc hosted services. Check out [Omega8.cc](https://omega8.cc/compare) for more info.

Thank you for supporting BOA!
