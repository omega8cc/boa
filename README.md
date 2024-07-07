# Welcome to BOA!

BOA stands for Barracuda, Octopus, and Ægir—a high-performance LEMP stack supporting Drupal from Pressflow 6 to the latest Drupal 10 (and soon Drupal 11), as well as Backdrop CMS and Grav CMS.

## What is Ægir?

Ægir, named after the Norse god of the sea, is an open-source hosting system for managing multiple Drupal sites. It automates tasks like site installation, upgrades, and maintenance, making your life easier.

### Key Features of Ægir:

- **Site Management**: Manage multiple Drupal sites from a single interface.
- **Automation**: Automate code deployment, database updates, and site backups.
- **Scalability**: Easily scale your Drupal hosting infrastructure.
- **Multitenancy**: Share a codebase across multiple sites with separate databases.
- **Open-Source**: Customize and extend Ægir to fit your needs.
- **Integration with Drush**: Use powerful command-line tools for site administration.

## Why Barracuda?

Barracuda is a specially tuned hosting environment for Ægir, designed to be lightning fast.

## Why Octopus?

Octopus is a smart system designed to manage multiple Ægir instances within Barracuda. Like the sea creature, it’s known for its intelligence and adaptability.

## BOA Priorities

- **High Performance**: Ensure your sites run fast.
- **Security**: Keep your sites and system secure.
- **Automation**: Minimize daily maintenance with automated system and OS upgrades.

## Multi-Ægir Hosting

Leverage one Aegir Master Instance and multiple Satellite Instances. Use Satellite Instances to host your sites, as the Master holds the central Nginx configuration. Note: The 'Master' and 'Satellite' names in the Barracuda/Octopus context are not related to the multi-server Aegir features but to the multi-instance environment with virtual chroot/jail for each Aegir Satellite instance.

## Installation Scripts

- **Barracuda**: Installs and upgrades the Aegir Master Instance system including OS environment and main Aegir instance, but no platforms (besides hostmaster) are installed there.
- **Octopus**: Installs and updates Aegir + Drupal platforms with a clean, secure structure.

## Dual License

Check out the details in [docs/DUALLICENCE.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/DUALLICENCE.md).

## Bug Reporting

Follow the guidelines in [docs/CONTRIBUTING.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/CONTRIBUTING.md).

## Requirements

- Basic sysadmin skills and experience.
- Willingness to accept BOA PI (paranoid idiosyncrasies).
- Minimum 4 GB RAM and 2 CPUs (8 GB RAM and 4+ CPUs with Solr).
- SSH (RSA) keys for root are required by newer OpenSSH versions used in BOA.
- Wget must be installed.
- Open outgoing TCP ports: 25, 53, 80, 443.
- Locales with UTF-8 support, otherwise en_US.UTF-8 (default) is forced.

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

- Daedalus (fully supported)
- Chimaera (supported but upgrade recommended)
- Beowulf (supported for upgrades)

### Debian (for migration)

- Bookworm (supported only as a base for migration to Devuan)
- Bullseye (supported only as a base for migration to Devuan)
- Buster (supported only as a base for migration to Devuan)
- Stretch (deprecated but still works, please upgrade to Chimaera)
- Jessie (deprecated but still works, please upgrade to Chimaera)

## Documentation and Templates

- Installation Instructions: [docs/INSTALL.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/INSTALL.md)
- Upgrade Instructions: [docs/UPGRADE.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/UPGRADE.md)
- Auto-Upgrade Instructions: [docs/AUTOUPGRADE.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/AUTOUPGRADE.md)
- Configuration Templates: [docs/cnf/barracuda.cnf](https://github.com/omega8cc/boa/tree/5.x-dev/docs/cnf/barracuda.cnf), [docs/cnf/octopus.cnf](https://github.com/omega8cc/boa/tree/5.x-dev/docs/cnf/octopus.cnf)
- System Control Files Index: [docs/ctrl/system.ctrl](https://github.com/omega8cc/boa/tree/5.x-dev/docs/ctrl/system.ctrl)

## Additional Documentation

- Self-Upgrade How-To: [docs/SELFUPGRADE.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/SELFUPGRADE.md)
- Composer: [docs/COMPOSER.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/COMPOSER.md)
- Dev-Mode Notes: [docs/DEVELOPMENT.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/DEVELOPMENT.md)
- Drush: [docs/DRUSH.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/DRUSH.md)
- Fast DB Operations: [docs/MYQUICK.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/MYQUICK.md)
- Fast Migrate/Clone: [docs/FASTTRACK.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/FASTTRACK.md)
- FAQ: [docs/FAQ.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/FAQ.md)
- Included Platforms: [docs/PLATFORMS.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/PLATFORMS.md)
- Let’s Encrypt: [docs/SSL.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/SSL.md)
- Migration (Octopus Instance): [docs/MIGRATE.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/MIGRATE.md)
- Migration (Single Site): [docs/REMOTE.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/REMOTE.md)
- Modules: [docs/MODULES.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/MODULES.md)
- New Relic: [docs/NEWRELIC.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/NEWRELIC.md)
- PHP Configuration: [docs/PHP.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/PHP.md)
- Remote S3 Backups: [docs/BACKUPS.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUPS.md)
- Nginx Rewrites: [docs/REWRITES.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/REWRITES.md)
- RVM, Compass Tools, NPM: [docs/RVM.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/RVM.md)
- Security Settings: [docs/SECURITY.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/SECURITY.md)
- Solr: [docs/SOLR.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/SOLR.md)
- Extra Comments: [docs/CAVEATS.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/CAVEATS.md)
- SSH Encryption: [docs/BLOWFISH.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BLOWFISH.md)
- VServer Cluster: [docs/CLUSTER.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/CLUSTER.md) (deprecated)

## Useful Links

- BOA User Handbook: [Learn BOA](https://learn.omega8.cc/library/good-to-know)
- Aegir Docs: [Aegir Project](https://docs.aegirproject.org)

## Maintainers

BOA is maintained by [Omega8.cc](https://omega8.cc/about).

## Credits

Thanks to the Aegir Project founders and developers. [Aegir Team](https://docs.aegirproject.org/community/core-team/).

## Support

Support BOA development by purchasing a commercial license or using Omega8.cc hosted services. Check out [Omega8.cc](https://omega8.cc/compare) for more info.

Thank you for supporting BOA!
