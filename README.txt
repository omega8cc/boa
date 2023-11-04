
### README

BOA is an acronym of high performance Barracuda, Octopus and Aegir LEMP stack.

Includes all-in-one bash scripts (see docs/INSTALL.txt for details) to install
and upgrade high performance Aegir Hosting Systems for Drupal, with Nginx,
PHP-FPM, Zend OPcache, Percona and Redis.


###--------------------------------------------------------------------------###
###
### Installation Instructions .........: docs/INSTALL.txt
### Other Related Information .........: docs/NOTES.txt
### Upgrade Instructions ..............: docs/UPGRADE.txt
### Bug Reporting .....................: CONTRIBUTING.txt <----- Read This First
###
### Barracuda Configuration Template ..: docs/cnf/barracuda.cnf
### Octopus Configuration Template ....: docs/cnf/octopus.cnf
### System Control Files Index ........: docs/ctrl/system.ctrl
###
### Platform and Site Level INI Templates:
###
###   aegir/conf/default.boa_platform_control.ini
###   aegir/conf/default.boa_site_control.ini
###
### Advanced Password Encryption ......: docs/BLOWFISH.txt
### BOA Self-Upgrade How-To ...........: docs/SELFUPGRADE.txt
### Cluster and Linux VServer How-To ..: docs/CLUSTER.txt
### Composer How-To ...................: docs/COMPOSER.txt
### Dev-Mode Notes ....................: docs/DEVELOPMENT.txt
### Drupalgeddon How-To ...............: docs/DRUPALGEDDON.txt
### FAST DB Operations How-To .........: docs/MYQUICK.txt
### Frequently Asked Questions ........: docs/FAQ.txt
### HHVM Support ......................: docs/HHVM.txt
### Let's Encrypt Support .............: docs/SSL.txt
### Migration - Octopus Instance ......: docs/MIGRATE.txt
### Migration - Single Site ...........: docs/REMOTE.txt
### Modules Enabled or Disabled .......: docs/MODULES.txt
### New Relic How-To ..................: docs/NEWRELIC.txt
### PHP Configuration How-To ..........: docs/PHP.txt
### Platforms Configuration Symbols ...: docs/PLATFORMS.txt
### Remote S3 Backups .................: docs/BACKUPS.txt
### Rewrites in Nginx .................: docs/REWRITES.txt
### RVM, Compass Tools, and NPM .......: docs/RVM.txt
### Security Related Settings .........: docs/SECURITY.txt
### Solr How-To .......................: docs/SOLR.txt
### Some Extra Comments ...............: docs/CAVEATS.txt
###
###--------------------------------------------------------------------------###


You can install one Aegir Master Instance and any number of Aegir Satellite
Instances. The Master Instance holds the central Nginx configuration for all
Satellite Instances and thus shouldn't be used to host your sites. Please
always use one or more Satellite Instances to host your sites.

The 'Master' and 'Satellite' names in the Barracuda/Octopus context are not
related to the multi-server Aegir features. It is related to the multi-instance
environment, with virtual chroot/jail for every Aegir Satellite instance.

Barracuda is the main script for the Aegir Master Instance system install and
upgrades, including OS environment and main Aegir instance, but no platforms
(besides hostmaster) are installed there.

Octopus is an Aegir + Platforms installer (you can interactively choose
the platforms you wish to install on the instance) and updater only. It allows
to install new versions of platforms with clean directory structure, with code
shared between all created instances, so one vanilla Octopus instance is using
only 35 MB, while most of the code, which is over 1400 MB in total, is shared.

Sharing the code between instances is of critical importance, because it allows
you to dramatically lower RAM and CPU usage, because most of the actively used
code is opcode cached. Note that shared codebase is used only in Drupal 7 and
Pressflow 6 distros, since Drupal 8 and newer don't support codebase symlinking.

With multi-install system you have to remember that all of them will use the
same Nginx server, so you could break the system trying to install site with
the same domain on two or more instances. The instances will not be aware of
other running instances, so it is your responsibility to use such system wisely.

There is also Tuner script available (see aegir/tools/BOND.sh.txt) for easy
system tuning for development and switching it back easily to the standard
production settings.


### SUPPORTED VIRTUALIZATION SYSTEMS {c} please read also: docs/CAVEATS.txt

* Linux KVM guest
* Linux VServer guest
* Microsoft Hyper-V
* Parallels guest
* VirtualBox guest
* VMware ESXi guest
* Xen guest


### Automatic BOA System Major Upgrade Tool now available

=> You can easily upgrade your system from any supported Debian version,
   starting with Debian Jessie, to latest Devuan Chimaera which is BOA
   preferred and systemd-free equivalent of Debian Bullseye.

   Please read docs/UPGRADE.txt for details.


### DEVUAN & DEBIAN {c} please read also: docs/CAVEATS.txt

##== Devuan @ https://www.devuan.org/os/releases

  * Devuan Chimaera (fully supported)
  * Devuan Beowulf (fully supported)

##== Debian @ https://wiki.debian.org/LTS

  * Debian 11 Bullseye (fully supported, but migration to Chimaera recommended)
  * Debian 10 Buster (supported but not recommended, please upgrade to Beowulf)
  * Debian 9 Stretch (deprecated but still works, please upgrade to Beowulf)
  * Debian 8 Jessie (deprecated but still works, please upgrade to Beowulf)

##== Ubuntu @ https://ubuntu.com/about/release-cycle

  * Ubuntu Trusty Tahr 14.04 LTS (deprecated and no longer tested)
  * Ubuntu Precise Pangolin 12.04.3 LTS (deprecated and no longer tested)


### OTHER REQUIREMENTS

* Basic sysadmin skills and experience.
* Willingness to accept BOA PI (paranoid idiosyncrasies).
* Minimum 4 GB RAM and 2 CPU (with Solr minimum 8 GB RAM and 4+ CPU).
* SSH (RSA) keys for root are required by newer OpenSSH versions used in BOA.
* Wget must be installed.
* The outgoing TCP connections via ports: 25, 53, 80 and 443 must be open.
* Locales with UTF-8 support, otherwise en_US.UTF-8 (default) is forced.


### PROVIDES

=== Included/enabled by default - see docs/NOTES.txt for details

* PHP-FPM 8.2/1/0 7.4/3/2/1/0 5.6 in multi-install mode, configurable per site.
* Latest release of Percona 5.7 database server with Adminer manager.
* All libraries & tools required to install and run Nginx based Aegir system.
* Magic Speed Booster cache, working like a Boost + AuthCache, but per user.
* Entry level XSS built-in protection on the Nginx level.
* Firewall csf/lfd integrated with Nginx abuse guard.
* Autonomous Maintenance & Auto-Healing scripts in /var/xdrago.
* Every 3 seconds uptime/self-healing local monitoring.
* Automated, rotated daily backups for all databases in /data/disk/arch/sql.
* Letsencrypt.org SSL support - see docs/SSL.txt for details.
* HTTP/2 or SPDY Nginx support.
* PFS (Perfect Forward Secrecy) support in Nginx.
* PHP extensions: Zend OPcache, PHPRedis, UploadProgress, MailParse and ionCube.
* Fast Redis Cache/Lock/Path with DB auto-failover for all Drupal core versions.
* Limited Shell, SFTP and FTPS accounts per Aegir Client with per site access.
* Drush access on command line in all shell accounts.
* Composer and Drush Make access on command line for main shell account only.
* PHP errors debugging, including WSOD, enabled on the fly on .dev. aliases.
* Built-in collection of useful modules available in all platforms.
* Fast DNS Cache Server (pdnsd)

=== Optional add-ons - see docs/NOTES.txt for details

* MultiCore Apache Solr 7 and Solr 4 - see docs/SOLR.txt for details
* New Relic Apps Monitor with per Octopus license and per Site reporting
* RVM, Compass Tools, and NPM - see docs/RVM.txt for details
* Image Optimize toolkit binaries
* FFmpeg support
* Bind9 DNS server
* Collectd server monitor (deprecated)
* LDAP Nginx support via third-party module (experimental)
* MongoDB driver for PHP (experimental)
* GEOS extension for PHP (experimental)
* Chive database manager (deprecated)
* SQL Buddy database manager (deprecated)
* HHVM support - see docs/HHVM.txt for details (deprecated)
* Webmin Control Panel (deprecated)


### OCTOPUS PLATFORMS

Octopus can install and/or support the platforms listed below:

 @ Drupal 10

 Drupal 10.1.6 -------------- https://drupal.org/project/drupal/releases/10.1.6
 Drupal 10.0.11 ------------- https://drupal.org/project/drupal/releases/10.0.11
 Social 12.0.0-rc3 ---------- https://drupal.org/project/social (10.0.11)
 Thunder 7.1.2 -------------- https://drupal.org/project/thunder (10.1.6)
 Varbase 9.0.16 ------------- https://drupal.org/project/varbase (10.1.6)

 @ Drupal 9

 Drupal 9.5.11 -------------- https://drupal.org/project/drupal/releases/9.5.11
 OpenLucius 2.0.0 ----------- https://drupal.org/project/openlucius (9.5.11)
 Opigno LMS 3.1.0 ----------- https://drupal.org/project/opigno_lms (9.5.11)

 @ Drupal 7.98.1

 Commerce 1.72 -------------- https://drupal.org/project/commerce_kickstart
 Commerce 2.77 -------------- https://drupal.org/project/commerce_kickstart
 Drupal 7.98.1 -------------- https://drupal.org/project/drupal/releases/7.98
 Guardr 2.57 ---------------- https://drupal.org/project/guardr
 OpenAtrium 2.652 ----------- https://drupal.org/project/openatrium
 OpenOutreach 1.69 ---------- https://drupal.org/project/openoutreach
 Opigno LMS 1.59 ------------ https://drupal.org/project/opigno_lms
 Panopoly 1.92 -------------- https://drupal.org/project/panopoly
 Ubercart 3.13 -------------- https://drupal.org/project/ubercart

 @ Pressflow (D6 LTS included, thanks to myDropWizard) 6.60.1

 Pressflow 6.60.1 ----------- https://www.pressflow.org
 Ubercart 2.15 -------------- https://drupal.org/project/ubercart

* All D7 platforms have been enhanced using Drupal 7.98.1 +Extra core:
  https://github.com/omega8cc/7x/tree/7.x-om8

* All D6 platforms have been enhanced using Pressflow (LTS) 6.60.1 +Extra core:
  https://github.com/omega8cc/pressflow6/tree/pressflow-plus

* All D6 and D7 platforms include some useful and/all performance related
  contrib modules - see docs/MODULES.txt for details.


### MAINTAINERS

BOA development is maintained and sponsored by Omega8.cc

  https://omega8.cc/about


### CREDITS

* Aegir project --------------- http://www.aegirproject.org
* Brian Mercer ---------------- https://drupal.org/node/244072#comment-1747170
* Nice people who are submitting patches and reporting bugs.


### DONATIONS

If you wish to support BOA development or simply send a nice 'Thank you'
to the Universe, please donate to the Aegir project. BOA devs participated
in Aegir core development for years, and BOA project, which is maintained
by Omega8.cc exists only thanks to Aegir project continued development.

You can donate using PayPal, Liberapay, Bitcoin or through Open Collective at:

  https://www.aegirproject.org/#donate


### HOSTED BOA & AFFILIATE PROGRAM with permanent 10% commissions

You can also support BOA development by using Omega8.cc hosted service:

  https://omega8.cc/compare
  https://omega8.cc/pricing
  https://omega8.cc/clusterpro

There is very attractive Affiliate Program available for all paying Clients:

  https://omega8.cc/affiliates

Thank you for your support!
