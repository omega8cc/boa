
### README

BOA is an acronym of high performance Barracuda, Octopus and Aegir LEMP stack.

Includes all-in-one bash scripts (see docs/INSTALL.txt for details) to install
and upgrade high performance Aegir Hosting Systems for Drupal, with Nginx,
PHP-FPM, Zend OPcache, MariaDB and Redis.


###--------------------------------------------------------------------------###
###
### Installation instructions .........: docs/INSTALL.txt
### Other related information .........: docs/NOTES.txt
### Upgrade instructions ..............: docs/UPGRADE.txt
### Bug reporting .....................: CONTRIBUTING.txt <----- Read This First
###
### Barracuda configuration template ..: docs/cnf/barracuda.cnf
### Octopus configuration template ....: docs/cnf/octopus.cnf
### System control files index ........: docs/ctrl/system.ctrl
###
### Platform and site level INI templates:
###
###   aegir/conf/default.boa_platform_control.ini
###   aegir/conf/default.boa_site_control.ini
###
### Advanced password encryption ......: docs/BLOWFISH.txt
### Custom Nginx rewrites .............: docs/HINTS.txt
### HHVM support ......................: docs/HHVM.txt
### Modules enabled or disabled .......: docs/MODULES.txt
### MultiCore Solr Jetty ..............: docs/SOLR.txt
### Octopus batch migration ...........: docs/MIGRATE.txt
### Platforms configuration symbols ...: docs/PLATFORMS.txt
### Remote S3 backups .................: docs/BACKUPS.txt
### RVM, Compass Tools, and NPM .......: docs/RVM.txt
### Security related settings .........: docs/SECURITY.txt
### Single site migration .............: docs/REMOTE.txt
### SSL with single or extra IP .......: docs/SSL.txt
### FAQ ...............................: docs/FAQ.txt
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
code is opcode cached.

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
* Parallels guest
* VirtualBox guest
* VMware ESXi guest
* Xen guest


### SUPPORTED LTS OS {c} please read also: docs/CAVEATS.txt

* Debian 8 Jessie (recommended)
* Debian 7 Wheezy (upgrade to Jessie with _WHEEZY_TO_JESSIE=YES)
* Debian 6 Squeeze (limited to upgrade to Wheezy with _SQUEEZE_TO_WHEEZY=YES)
* Ubuntu Trusty 14.04 (limited support)
* Ubuntu Precise 12.04 (limited support)


### OTHER REQUIREMENTS

* SSH keys for root are required by newer OpenSSH versions used in BOA.
* Wget must be installed.
* The outgoing TCP connections via ports: 25, 53, 80 and 443 must be open.
* Minimum 1 GB of RAM (at least 2GB of RAM + at least 2 CPU recommended)
* Locales with UTF-8 support, otherwise en_US.UTF-8 (default) is forced.
* Basic sysadmin skills and experience.
* Willingness to accept BOA PI (paranoid idiosyncrasies).


### PROVIDES

=== Included/enabled by default - see docs/NOTES.txt for details

* All libraries & tools required to install and run Nginx based Aegir system.
* Latest release of MariaDB 5.5 or 10.0 database server with Adminer manager.
* Latest version of Nginx web server.
* Letsencrypt.org SSL support - see docs/SSL.txt for details.
* HTTPS access with self-signed certificate for all hosted sites.
* HTTP/2 or SPDY Nginx support.
* PFS (Perfect Forward Secrecy) support in Nginx.
* PHP-FPM 7.0, 5.6, 5.5, 5.4, 5.3 multi-install mode, configurable per site.
* PHP extensions: Zend OPcache, PHPRedis, UploadProgress, MailParse and ionCube.
* Fast Redis Cache with DB auto-failover for all 6.x and 7.x platforms.
* Fast Redis Lock support with DB auto-failover for all 6.x and 7.x platforms.
* Fast Redis Path support with DB auto-failover for all 6.x and 7.x platforms.
* Fast proxy DNS server (pdnsd) with permanent caching.
* Limited Shell, SFTP and FTPS separate accounts per Octopus instance.
* Limited Shell, SFTP and FTPS accounts per Aegir Client with per site access.
* Drush access on command line in all shell accounts.
* Drush Make access on command line for main shell account only.
* Support for New Relic monitoring with per Octopus instance license key.
* Solr 4 cores can be added/updated/deleted via site level INI settings.
* Magic Speed Booster cache, working like a Boost + AuthCache, but per user.
* Entry level XSS built-in protection on the Nginx level.
* Firewall csf/lfd integrated with Nginx abuse guard.
* PHP errors debugging, including WSOD, enabled on the fly on .dev. aliases.
* Boost, AdvAgg, Domain Access and Drupal for Facebook built-in support.
* Built-in collection of useful modules available in all platforms.
* Autonomous Maintenance & Auto-Healing scripts in /var/xdrago.
* Every 3 seconds uptime/self-healing local monitoring.
* Automated, rotated daily backups for all databases in /data/disk/arch/sql.

=== Optional add-ons - see docs/NOTES.txt for details

* Compass Tools - see https://omega8.cc/node/329 for details.
* HHVM support - see docs/HHVM.txt for details.
* MultiCore Apache Solr 4.9.1 with Jetty 9 - see docs/SOLR.txt for details.
* New Relic Apps Monitor with per Octopus license and per Site reporting.
* Image Optimize toolkit binaries.
* FFmpeg support.
* Bind9 DNS server.
* Webmin Control Panel.
* Chive database manager
* SQL Buddy database manager.
* Collectd server monitor.
* LDAP Nginx support via third-party module (experimental).
* MongoDB driver for PHP (experimental).
* GEOS extension for PHP (all supported PHP versions).


### OCTOPUS PLATFORMS

Octopus can install and/or support the platforms listed below:

 @ Drupal 8

 Drupal 8 support for custom platforms in the ~/static directory tree
 has been added, along with Drush 8, in the BOA-3.0.0 release.
 Note: BOA will not include built-in Drupal 8 platforms until Drupal 8
 will support symlinks in the codebase, like all previous core versions.

 See also: https://omega8.cc/how-to-add-custom-platform-properly-140

 @ Drupal 7.50.1

 aGov 3.2 --------------------- https://drupal.org/project/agov
 Commerce 1.43 ---------------- https://drupal.org/project/commerce_kickstart
 Commerce 2.38 ---------------- https://drupal.org/project/commerce_kickstart
 Commons 3.38 ----------------- https://drupal.org/project/commons
 Drupal 7.50.1 ---------------- https://drupal.org/blog/drupal-7-50
 Guardr 2.34 ------------------ https://drupal.org/project/guardr
 OpenAid 2.8 ------------------ https://drupal.org/project/openaid
 OpenAtrium 2.66 -------------- https://drupal.org/project/openatrium
 OpenChurch 2.2 --------------- https://drupal.org/project/openchurch
 OpenOutreach 1.31 ------------ https://drupal.org/project/openoutreach
 OpenPublic 1.9 --------------- https://drupal.org/project/openpublic
 Panopoly 1.38 ---------------- https://drupal.org/project/panopoly
 Restaurant 1.13 -------------- https://drupal.org/project/restaurant
 Ubercart 3.10 ---------------- https://drupal.org/project/ubercart

 @ Pressflow 6.38.2

 Commons 2.27 ----------------- https://drupal.org/project/commons
 Pressflow 6.38.2 ------------- http://pressflow.org
 Ubercart 2.15 ---------------- https://drupal.org/project/ubercart

* All D7 platforms have been enhanced using Drupal 7.50.1 +Extra core:
  https://github.com/omega8cc/7x/tree/7.x-om8

* All D6 platforms have been enhanced using Pressflow 6.38.2 +Extra core:
  https://github.com/omega8cc/pressflow6/tree/pressflow-plus

* All D6 and D7 platforms include some useful and/all performance related
  contrib modules - see docs/MODULES.txt for details.


### MAINTAINERS

BOA development is maintained and sponsored by Omega8.cc

  https://omega8.cc/about


### CREDITS

* Aegir project --------------- http://www.aegirproject.org
* Brian Mercer ---------------- https://drupal.org/node/244072#comment-1747170
* Nice people who are submitting bugs and problems in the BOA issue queue.


### DONATIONS

If you wish to support BOA development or simply send a nice 'Thank you'
to the Universe, please donate to the Aegir project. BOA devs participate
in Aegir core development for years, and BOA project, which is maintained
by Omega8.cc exists only thanks to Aegir project continued development.

Please choose either PayPal or Gratipay option at:

  http://www.aegirproject.org/donate

Thank you!
