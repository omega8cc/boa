
###
### READ ME IN FULL PLEASE
###

BOA is an acronym of high performance Barracuda, Octopus and Aegir LEMP stack,
supporting hosting Drupal versions from Pressflow 6 to latest Drupal 10.

Includes all-in-one bash scripts (see docs/INSTALL.txt for details) to install
and upgrade high performance Aegir Hosting System for Drupal, with Nginx,
PHP-FPM, Zend OPcache, Percona and Redis.

You can install one Aegir Master Instance and any number of Aegir Satellite
Instances. The Master Instance holds the central Nginx configuration for all
Satellite Instances and thus shouldn't be used to host your sites. Please
always use one or more Satellite Instances to host your sites.

The 'Master' and 'Satellite' names in the Barracuda/Octopus context are not
related to the multi-server Aegir features. It is related to the multi-instance
environment, with virtual chroot/jail for every Aegir Satellite instance.

BOA stack doesn't support nor leverage Aegir Remote Servers feature currently.
However, there are plans to add Remote Servers as an option in the future.

While BOA provide tools for easy migrations of entire Aegir instances between
remote BOA servers, it doesn't support migrating sites between Aegir instances
on the same BOA server -- at least not yet.

Barracuda is the main script for the Aegir Master Instance system install and
upgrades, including OS environment and main Aegir instance, but no platforms
(besides hostmaster) are installed there.

Octopus is an Aegir + Platforms installer (you can interactively choose
the platforms you wish to install on the instance) and updater only. It allows
to install new versions of platforms with clean directory structure, with code
shared between all created instances, so one vanilla Octopus instance is using
only 35 MB, while most of the code, which is over 1400 MB in total, is shared.

Sharing the code between instances is of critical importance, especially in the
large hosting environments with many platforms across many Satellite instances,
because it allows you to dramatically lower RAM and CPU usage thanks to opcode
caching. Note however that shared codebase is supported only in Drupal 7 and
Pressflow 6 distros, since Drupal 8 and newer don't support codebase symlinking.

With multi-Aegir-instance system you have to remember that all of them will use
the same Nginx server, so you could affect others trying to install site with
the same domain on two or more instances. The instances will not be aware of
other running instances, so it is your responsibility to use such system wisely.

To be precise, the possible conflict between sites will not affect their files
nor databases, only their visibility, because Nginx will load only the first
vhost with the same name and ignore the others, so the instance which is loaded
first in the alphabetical order of their system users names, will take it over.

It's also critically important to never give anyone access to Aegir system user
on any Octopus instance, because it comes with almost root access to *all* sites
databases hosted across all Octopus instances on the same BOA server. Only
the limited shell access accounts and non-admin Aegir control panel accounts
should be ever provided for your end-users.

There is also Tuner script available (see aegir/tools/BOND.sh.txt) for easy
system tuning for development and switching it back easily to the standard
production settings.

@=> DUAL LICENCE NOTICE

  While all BOA code is Free/Libre Open Source, only the BOA main installer
  and Aegir itself is free of charge without limits, while both Barracuda and
  Octopus updaters are paid upgrade service, with an effective date of
  January 1st, 2024.

  There are exceptions explained further below, though.

  The reasoning behind this change is simple. Normally Open Source software
  benefits from its users contributions, both technically (patches) and
  financially (donations).

  We have carefully reviewed both Aegir and BOA projects history in these two
  areas and concluded that both Aegir and BOA received only sporadic technical
  support (patches) while financial support (donations) was basically
  nonexistent.

  This resulted with developers either leaving theses projects or moving in
  different, incompatible directions, because all developers were forced to
  limit, focus or switch their attention and work on something only their
  clients were interested in.

  This affected also us at omega8.cc because BOA includes many things we don't
  use in our commercial hosting, it was from the beginning written with the
  very verbose coding style making it available for reading and improving.

  The resulting maintenance overhead became too big for us to handle and
  at some point we have considered closing the project for the public. However,
  many BOA users voiced their interest in keeping BOA alive, so we have spent
  the last year on taking steps and preparations to find viable solution.

  We know that most of BOA users are running BOA for commercial purposes,
  effectively creating competition for our hosted BOA service, while not paying
  anything and not supporting BOA nor Aegir in any other way.

  We have concluded that it's unfair situation and that in the absence of
  voluntary support for Aegir and BOA we have hoped for over years, the
  decision has to be made to introduce dual-licence model for BOA use.

  This change will not limit any BOA user from running system upgrades with
  standard Debian/Devuan tools, but both barracuda and octopus upgrades will
  require valid licence after January 1st, 2024

  There will be a test-drive period for new servers to run both barracuda and
  octopus upgrades during the first 90 days, while all servers installed before
  January 1st, 2024 will enjoy the 30 days of free extension after that date.

  The pricing will be announced on https://omega8.cc/compare page shortly.


@=> FOR BUG REPORTING PLEASE FOLLOW GUIDELINES EXPLAINED IN CONTRIBUTING.txt


@=> SUPPORTED VIRTUALIZATION SYSTEMS -- please read also: docs/CAVEATS.txt

  * Linux Containers (LXC) guest
  * Linux KVM guest
  * Linux VServer guest
  * Microsoft Hyper-V guest
  * OpenVZ Containers guest
  * Parallels guest
  * VirtualBox guest
  * VMware ESXi guest
  * Xen guest


@=> SUPPORTED OPERATING SYSTEMS -- please read also: docs/CAVEATS.txt

  Devuan @ https://www.devuan.org/os/releases

  * Devuan Chimaera (fully supported and the only OS version recommended)
  * Devuan Beowulf (supported only as a base for upgrade to Chimaera)

  Debian @ https://wiki.debian.org/LTS

  * Debian 11 Bullseye (supported only as a base for migration to Devuan)
  * Debian 10 Buster (supported only as a base for migration to Devuan)
  * Debian 9 Stretch (deprecated but still works, please upgrade to Devuan)
  * Debian 8 Jessie (deprecated but still works, please upgrade to Devuan)


@=> REQUIREMENTS

  * Basic sysadmin skills and experience.
  * Willingness to accept BOA PI (paranoid idiosyncrasies).
  * Minimum 4 GB RAM and 2 CPU (with Solr minimum 8 GB RAM and 4+ CPU).
  * SSH (RSA) keys for root are required by newer OpenSSH versions used in BOA.
  * Wget must be installed.
  * The outgoing TCP connections via ports: 25, 53, 80 and 443 must be open.
  * Locales with UTF-8 support, otherwise en_US.UTF-8 (default) is forced.


@=> PROVIDES

  *Included/enabled by default -- see docs/NOTES.txt for details

  Automatic BOA System Major Upgrade Tool -- see docs/UPGRADE.txt for details.
  PHP-FPM 8.2/1/0 7.4/3/2/1/0 5.6 in multi-install mode, configurable per site.
  Latest release of Percona 5.7 database server with Adminer manager.
  All libraries & tools required to install and run Nginx based Aegir system.
  Magic Speed Booster cache, working like a Boost + AuthCache, but per user.
  Entry level XSS built-in protection on the Nginx level.
  Firewall csf/lfd integrated with Nginx abuse guard.
  Autonomous Maintenance & Auto-Healing scripts in /var/xdrago.
  Every 3 seconds uptime/self-healing local monitoring.
  Automated, rotated daily backups for all databases in /data/disk/arch/sql.
  Letsencrypt.org SSL support -- see docs/SSL.txt for details.
  HTTP/2 or SPDY Nginx support.
  PFS (Perfect Forward Secrecy) support in Nginx.
  PHP extensions: Zend OPcache, PHPRedis, UploadProgress, MailParse and ionCube.
  Fast Redis Cache/Lock/Path with DB auto-failover for all Drupal core versions.
  Limited Shell, SFTP and FTPS accounts per Aegir Client with per site access.
  Drush access on command line in all shell accounts.
  Composer and Drush Make access on command line for main shell account only.
  PHP errors debugging, including WSOD, enabled on the fly on .dev. aliases.
  Built-in collection of useful modules available in all platforms.
  Fast DNS Cache Server (pdnsd)

  +Optional add-ons -- see docs/NOTES.txt for details

  MultiCore Apache Solr 7 and Solr 4 -- see docs/SOLR.txt for details
  New Relic Apps Monitor with per Octopus license and per Site reporting
  RVM, Compass Tools, and NPM -- see docs/RVM.txt for details
  Image Optimize toolkit binaries
  FFmpeg support
  Bind9 DNS server


@=> OCTOPUS PLATFORMS

 Octopus can install and/or support the Aegir platforms listed below:

 @ Drupal 10

 Drupal 10.1.6 -------------- https://drupal.org/project/drupal/releases/10.1.6
 Drupal 10.2.0 -------------- https://drupal.org/project/drupal/releases/10.2.0
 Drupal 10.0.11 ------------- https://drupal.org/project/drupal/releases/10.0.11
 Social 12.0.0-rc3 ---------- https://drupal.org/project/social (10.0.11)
 Thunder 7.1.2 -------------- https://drupal.org/project/thunder (10.1.6)
 Varbase 9.0.16 ------------- https://drupal.org/project/varbase (10.1.6)

 @ Drupal 9

 Drupal 9.5.11 -------------- https://drupal.org/project/drupal/releases/9.5.11
 OpenLucius 2.0.0 ----------- https://drupal.org/project/openlucius (9.5.11)
 Opigno LMS 3.1.0 ----------- https://drupal.org/project/opigno_lms (9.5.11)

 @ Drupal 7

 Commerce 1.72 -------------- https://drupal.org/project/commerce_kickstart
 Commerce 2.77 -------------- https://drupal.org/project/commerce_kickstart
 Drupal 7.99.1 -------------- https://drupal.org/project/drupal/releases/7.99
 Guardr 2.57 ---------------- https://drupal.org/project/guardr
 OpenAtrium 2.652 ----------- https://drupal.org/project/openatrium
 OpenOutreach 1.69 ---------- https://drupal.org/project/openoutreach
 Opigno LMS 1.59 ------------ https://drupal.org/project/opigno_lms
 Panopoly 1.93 -------------- https://drupal.org/project/panopoly
 Ubercart 3.13 -------------- https://drupal.org/project/ubercart

 @ Drupal 6

 Pressflow 6.60.1 ----------- https://www.pressflow.org
 Ubercart 2.15 -------------- https://drupal.org/project/ubercart

 * All D7 platforms have been enhanced using Drupal 7.99.1 +Extra core:
   https://github.com/omega8cc/7x/tree/7.x-om8

 * All D6 platforms have been enhanced using Pressflow (LTS) 6.60.1 +Extra core:
   https://github.com/omega8cc/pressflow6/tree/pressflow-plus

 * All D6 and D7 platforms include some useful and/all performance related
   contrib modules - see docs/MODULES.txt for details.


@=> DOCUMENTATION AND CONFIGURATION TEMPLATES

  Installation Instructions .........: docs/INSTALL.txt
  Other Related Information .........: docs/NOTES.txt
  Upgrade Instructions ..............: docs/UPGRADE.txt

  Barracuda Configuration Template ..: docs/cnf/barracuda.cnf
  Octopus Configuration Template ....: docs/cnf/octopus.cnf
  System Control Files Index ........: docs/ctrl/system.ctrl

  Platform and Site Level INI Templates:

    aegir/conf/default.boa_platform_control.ini
    aegir/conf/default.boa_site_control.ini

  BOA Self-Upgrade How-To ...........: docs/SELFUPGRADE.txt
  Composer How-To ...................: docs/COMPOSER.txt
  Dev-Mode Notes ....................: docs/DEVELOPMENT.txt
  Drush versions support and usage ..: docs/DRUSH.txt
  FAST DB Aegir Operations How-To ...: docs/MYQUICK.txt
  FAST Migrate/Clone Aegir How-To ...: docs/FASTTRACK.txt
  Frequently Asked Questions ........: docs/FAQ.txt
  Let's Encrypt Support .............: docs/SSL.txt
  Migration - Octopus Instance ......: docs/MIGRATE.txt
  Migration - Single Site ...........: docs/REMOTE.txt
  Modules Enabled or Disabled .......: docs/MODULES.txt
  New Relic How-To ..................: docs/NEWRELIC.txt
  PHP Configuration How-To ..........: docs/PHP.txt
  Platforms Configuration Symbols ...: docs/PLATFORMS.txt
  Remote S3 Backups .................: docs/BACKUPS.txt
  Rewrites in Nginx .................: docs/REWRITES.txt
  RVM, Compass Tools, and NPM .......: docs/RVM.txt
  Security Related Settings .........: docs/SECURITY.txt
  Solr How-To .......................: docs/SOLR.txt
  Some Extra Comments ...............: docs/CAVEATS.txt
  SSH Advanced Password Encryption ..: docs/BLOWFISH.txt
  VServer Cluster How-To ............: docs/CLUSTER.txt

  BOA user handbook -- legacy version but still useful:

    https://learn.omega8.cc/library/good-to-know

  Aegir own docs -- useful but some things don't apply in the BOA context:

    https://docs.aegirproject.org


@=> MAINTAINERS

  BOA development is maintained and sponsored by Omega8.cc

    https://omega8.cc/about


@=> CREDITS

  Aegir Project Founder, Emeritus and Current Developers

    https://docs.aegirproject.org/community/core-team/


@=> SUPPORT

  You can support BOA development by using Omega8.cc hosted service:

    https://omega8.cc/compare
    https://omega8.cc/pricing
    https://omega8.cc/clusterpro

  There is also an Affiliate Program available for all paying Clients:

    https://omega8.cc/affiliates

  Thank you for your support!
