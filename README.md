# Welcome to BOA!

BOA stands for Barracuda, Octopus, and Ægir—a high-performance LEMP stack supporting Drupal from Pressflow 6 to the latest Drupal 11 (which needs Percona 8.4, see [Install BOA](https://docs.boa.io/self-hosting/install-boa)), as well as **Backdrop CMS**, **Grav CMS** and **Textpattern CMS**.

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

## Documentation

All BOA documentation lives on [**docs.boa.io**](https://docs.boa.io), split into four guides, one per kind of reader:

- [**Using BOA**](https://docs.boa.io/using): for site owners on a hosted account.
- [**Self-Hosting BOA**](https://docs.boa.io/self-hosting): for running BOA on your own server.
- [**Operating BOA**](https://docs.boa.io/operating): the advanced root reference.
- [**Developing BOA**](https://docs.boa.io/developing): for BOA maintainers.

It also carries the [Ægir Platforms](https://docs.boa.io/platforms) catalogue, [cheat sheets](https://docs.boa.io/cheat-sheets), [release notes](https://docs.boa.io/releases), a searchable [reference](https://docs.boa.io/reference) of every control variable, control file and command, and the [changelog](https://docs.boa.io/changelog) of the documentation itself.

The documentation that used to ship in this repository's `docs/` directory was retired in October 2026, once everything in it had been carried over to the site. docs.boa.io is the single, current source.

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

## Install

BOA installs on a clean, minimal Devuan server, or on a Debian server, which the installer converts to Devuan for you. You need root SSH-key access, a wildcard-enabled hostname such as `server.mydomain.org` that already resolves to the server, and no web or database service installed. Log in as root directly, never through `sudo`, start a `screen` session, and run:

```sh
wget -qO- https://files.boa.io/BOA.sh.txt | bash
boa in-lts public server.mydomain.org my@email o1 php-min silent
```

Replace the hostname and the e-mail address with your own. The install runs its phases on its own, the last one from cron within 30 minutes of the others. Don't reboot and don't use Ægir until `boa info | grep -c Percona` reports three lines; then reboot once with `boa reboot`.

To host Drupal 11, or a distribution built on it, put `percona-8.4` where `php-min` is: BOA installs Percona 5.7 by default, and Drupal 11 needs MySQL 8. Every install option, the local-development install and what to do when an install is interrupted are on [**Install BOA**](https://docs.boa.io/self-hosting/install-boa); the server checklist is on [**Before you install**](https://docs.boa.io/self-hosting/before-you-install).

## Upgrade

Leave SKYNET on: it keeps the system patched between BOA releases and e-mails you when a new release is out. To run a full upgrade by hand, as root in a `screen` session:

```sh
wget -qO- https://files.boa.io/BOA.sh.txt | bash
barracuda up-lts
octopus up-lts all force
```

On the PRO edition the verb is `up-pro`. Append `log` to either command for the silent, logged mode that e-mails the report instead of printing it. A Percona 5.7 server moves to 8.4 in place, in two steps, `barracuda up-lts system percona-8.0` and then `percona-8.4`, after a whole-server snapshot and a `codebasecheck --box --deep` run. The whole procedure, the partial upgrade modes and the self-upgrade schedule are on [**Keeping BOA current**](https://docs.boa.io/self-hosting/keeping-current).

## Bug Reporting

Report bugs in the [GitHub issue queue](https://github.com/omega8cc/boa/issues), following [**Contributing to BOA**](https://docs.boa.io/developing/contributing/contributing). Every report needs a Gist with the output of `boa info`.

## Requirements

- Basic sysadmin skills and experience.
- Willingness to accept BOA PI (paranoid idiosyncrasies).
- Minimum 4 GB RAM and 2 CPUs (8 GB RAM and 4+ CPUs with Solr).
- SSH (ed25519) keys for root are required by newer OpenSSH versions used in BOA.
- Wget must be installed.
- Open outgoing TCP ports: 25, 53, 80, 443.
- Open incoming TCP ports 22, 80, 443 and UDP port 443 (HTTP/3): [HTTP/3 and KTLS](https://docs.boa.io/operating/nginx-internals/http3-ktls).
- Locales with UTF-8 support, otherwise en_US.UTF-8 (default) is forced.

## Provided Services and Features

Check out what the stack adds on top of Ægir in [**Ægir vs BOA**](https://docs.boa.io/aegir-vs-boa), and the full reference in [**Operating BOA**](https://docs.boa.io/operating).

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

- Daedalus (Percona 5.7 or 8.4 for Drupal 11)
- Excalibur (supported, but only with Percona 8.4)
- Chimaera (deprecated, not tested in any context - upgrade to Daedalus)
- Beowulf (deprecated, not tested in any context - a hop on the way up only)

### Debian (for migration)

- Trixie (supported only as a base for migration to Devuan)
- Bookworm (supported only as a base for migration to Devuan)
- Bullseye (supported only as a base for migration to Devuan)
- Buster (supported only as a base for migration to Devuan)
- Stretch (deprecated, not tested - migrate up the chain to Devuan Daedalus)
- Jessie (deprecated, not tested - migrate up the chain to Devuan Daedalus)

## Project Roadmap

Check out the details in [**ROADMAP.md**](https://github.com/omega8cc/boa/tree/5.x-dev/ROADMAP.md)

## Useful Links

- BOA Documentation: [**docs.boa.io**](https://docs.boa.io)
- Release News and Announcements: [**omega8.cc/news**](https://omega8.cc/news)

## Maintainers

BOA is maintained by [**Omega8.cc**](https://omega8.cc/about).

## Credits

Thanks to the Ægir Project founders and developers. [**Ægir Team**](https://docs.aegirproject.org/community/core-team/).

## Support

Support BOA development by purchasing a commercial license or using Omega8.cc hosted services. Check out [**Omega8.cc**](https://omega8.cc/compare) for more info.

Thank you for supporting BOA!
