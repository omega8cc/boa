# Welcome to BOA!

BOA stands for Barracuda, Octopus, and Ægir—a high-performance LEMP stack supporting Drupal from Pressflow 6 to the latest Drupal 11, as well as Backdrop CMS and Grav CMS (soon).

## Strap in, your sites are getting an F1 engine

We’re rolling out a meaningful upgrade across BOA/Omega8.cc nodes: HTTP/3 and KTLS support. If you run Drupal sites that should feel fast and responsive (and stay that way during spikes), this is genuinely good news. Why this is a big deal? What visitors should notice? Why it matters for *your server* too [**Read the full story!**](https://github.com/omega8cc/boa/tree/5.x-dev/HTTP3.md)

## 30 Years of Heritage

We are unique within the hosting industry for many important reasons. Our 15 years of Ægir-based hosting, plus earlier experience with Adgrafix (the first company to offer a control panel for website management in 1995), have helped shape what makes us different today. We take **Open Source seriously** — it’s not a buzzword for us. It’s about freedom from corporate control. Here's a short look back at our 15-year Ægir journey and 19 years with Drupal. [**Read the full story!**](https://github.com/omega8cc/boa/tree/5.x-dev/DIFFERENT30Y.md)

## What is Ægir?

Ægir, named after the Norse god of the sea, is an open-source hosting system for managing multiple Drupal sites. The name Ægir was chosen to reflect the relationship between Drupal's water drop logo, symbolizing individual sites, and Ægir's role as the god of the ocean, representing the hosting of many Drupal sites together. It automates tasks such as site installation, upgrades, and maintenance, making your life easier.

**Announcement from Omega8.cc team**: [**The Future of Ægir 3 is Bryght!**](https://github.com/omega8cc/boa/tree/5.x-dev/ANNOUNCEMENT.md)

### Key Features of Ægir:

- **Site Management**: Manage multiple Drupal sites from a single interface.
- **Automation**: Automate code deployment, database updates, and site backups.
- **Scalability**: Easily scale your Drupal hosting infrastructure.
- **Multitenancy**: Share a codebase across multiple sites with separate databases.
- **Open-Source**: Customize and extend Ægir to fit your needs.
- **Integration with Drush**: Use powerful command-line tools for site administration.

<img width="1215" height="1264" alt="Ægir-BOA" src="https://github.com/user-attachments/assets/b2417cc7-2fb8-422c-96f8-71d12c1c2fd7" />

## Why Barracuda?

Barracuda is a specially tuned hosting environment for Ægir, designed to be lightning fast and agile, just like the barracuda fish known for its incredible speed and agility in the ocean.

## Why Octopus?

Octopus is a smart system designed to manage multiple Ægir instances within Barracuda. Just like the sea creature with eight limbs, Octopus allows you to create and manage many separate but connected Ægir instances, showcasing its intelligence and adaptability in efficiently handling complex hosting environments.

## Dual License

**BOA** remains a **Free/Libre Open Source Project**. While all of **BOA** code is **Free/Libre Open Source**, only the **BOA LTS** branch and **Ægir** are available without any cost or restrictions.

Check out the details in [**DUALLICENSE.md**](https://github.com/omega8cc/boa/tree/5.x-dev/DUALLICENSE.md).

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

Follow the guidelines in [**docs/CONTRIBUTING.md**](https://github.com/omega8cc/boa/tree/5.x-dev/docs/CONTRIBUTING.md).

## Requirements

- Basic sysadmin skills and experience.
- Willingness to accept BOA PI (paranoid idiosyncrasies).
- Minimum 4 GB RAM and 2 CPUs (8 GB RAM and 4+ CPUs with Solr).
- SSH (ed25519) keys for root are required by newer OpenSSH versions used in BOA.
- Wget must be installed.
- Open outgoing TCP ports: 25, 53, 80, 443.
- Locales with UTF-8 support, otherwise en_US.UTF-8 (default) is forced.

## Provided Services and Features

Check out the details in [**docs/PROVIDES.md**](https://github.com/omega8cc/boa/tree/5.x-dev/docs/PROVIDES.md).

## Supported Virtualization Systems

- Linux Containers (LXC)
- Linux KVM guest
- Microsoft Hyper-V
- OpenVZ Containers
- Parallels guest
- Red Hat KVM guest
- VirtualBox guest
- VMware ESXi guest (but excluding vCloud Air)
- VServer guest
- Xen guest
- Xen guest fully virtualized (HVM)
- Xen paravirtualized guest domain

## Supported Operating Systems

<img width="906" height="672" alt="boa-on-excalibur" src="https://github.com/user-attachments/assets/cdf4f72b-6d7d-4712-895b-46f612be333f" />

### Devuan (recommended)

- Excalibur (supported, but only with Percona 8.4)
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

Check out the details in [**ROADMAP.md**](https://github.com/omega8cc/boa/tree/5.x-dev/ROADMAP.md)

## Documentation and Templates

- Installation Instructions: [docs/INSTALL.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/INSTALL.md)
- Upgrade Instructions: [docs/UPGRADE.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/UPGRADE.md)
- Major-Upgrade Instructions: [docs/MAJORUPGRADE.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/MAJORUPGRADE.md)
- Importance of Keeping SKYNET Enabled in BOA: [docs/SKYNET.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/SKYNET.md)
- INI configuration per site: [docs/ini/site/INI.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/ini/site/INI.md)
- INI configuration per platform: [docs/ini/platform/INI.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/ini/platform/INI.md)
- Configuration Templates: [docs/cnf/barracuda.cnf](https://github.com/omega8cc/boa/tree/5.x-dev/docs/cnf/barracuda.cnf), [docs/cnf/octopus.cnf](https://github.com/omega8cc/boa/tree/5.x-dev/docs/cnf/octopus.cnf)
- System Control Files Index: [docs/ctrl/system.ctrl](https://github.com/omega8cc/boa/tree/5.x-dev/docs/ctrl/system.ctrl)
- How we build newer codebases for testing: [docs/BUILDTESTS.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BUILDTESTS.md)

## Documentation for BOA PRO

- New Backups for BOA SysAdmin [docs/BACKUP_ROOT.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_ROOT.md)
- New Backups for Octopus Lshell User [docs/BACKUP_USER.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_USER.md)
- New Backups Retention Policy Configuration [docs/BACKUP_RETENTION.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_RETENTION.md)
- Supported Regions and Bucket Creation Guidelines [docs/BACKUP_REGIONS.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUP_REGIONS.md)

## Additional Documentation

- Composer How-To: [docs/COMPOSER.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/COMPOSER.md)
- Dev-Mode Notes: [docs/DEVELOPMENT.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/DEVELOPMENT.md)
- Drupal Contrib Modules: [docs/MODULES.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/MODULES.md)
- Extra Comments: [docs/CAVEATS.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/CAVEATS.md)
- FAQ: [docs/FAQ.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/FAQ.md)
- Fast DB Operations: [docs/MYQUICK.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/MYQUICK.md)
- Fast Migrate/Clone: [docs/FASTTRACK.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/FASTTRACK.md)
- Included Platforms: [docs/PLATFORMS.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/PLATFORMS.md)
- Let’s Encrypt: [docs/SSL.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/SSL.md)
- Live Disk Resize How-To: [docs/DISK_RESIZE.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/DISK_RESIZE.md)
- Migration (Octopus Instance): [docs/MIGRATE.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/MIGRATE.md)
- Migration (Single Site): [docs/REMOTE.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/REMOTE.md)
- New Relic How-To: [docs/NEWRELIC.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/NEWRELIC.md)
- Nginx Custom Rewrites: [docs/REWRITES.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/REWRITES.md)
- PHP-CLI and Drush Configuration How-To: [docs/DRUSH-CLI.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/DRUSH-CLI.md)
- PHP-FPM Configuration How-To: [docs/PHP-FPM.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/PHP-FPM.md)
- Remote S3 Backups: [docs/BACKUPS.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BACKUPS.md)
- Ruby Gems and NPM: [docs/GEM.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/GEM.md)
- Security Settings: [docs/SECURITY.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/SECURITY.md)
- Self-Upgrade How-To: [docs/SELFUPGRADE.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/SELFUPGRADE.md)
- SMTP SSL Error Debugging: [docs/SMTP_SSL_DEBUG.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/SMTP_SSL_DEBUG.md)
- Solr and Jetty How-To: [docs/SOLR.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/SOLR.md)
- SSH Encryption: [docs/BLOWFISH.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/BLOWFISH.md)
- VServer Cluster: [docs/CLUSTER.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/CLUSTER.md) (deprecated)

## Useful Links

- BOA User Handbook (legacy): [**Learn BOA**](https://learn.omega8.cc/library/good-to-know)
- Ægir Docs (legacy): [**Ægir Project**](https://docs.aegirproject.org)

## Maintainers

BOA is maintained by [**Omega8.cc**](https://omega8.cc/about).

## Credits

Thanks to the Ægir Project founders and developers. [**Ægir Team**](https://docs.aegirproject.org/community/core-team/).

## Support

Support BOA development by purchasing a commercial license or using Omega8.cc hosted services. Check out [**Omega8.cc**](https://omega8.cc/compare) for more info.

Thank you for supporting BOA!
