
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
### RVM and Compass Tools .............: docs/RVM.txt
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


### SUPPORTED PARENT SYSTEMS {c} please read also: docs/CAVEATS.txt

* Xen, VServer, Linux KVM or VMware based VPS or a dedicated box.


### SUPPORTED LTS OS {c} please read also: docs/CAVEATS.txt

* Debian 7 Wheezy (recommended)
* Debian 6 Squeeze (limited support with automatic upgrade to Wheezy)
* Ubuntu Trusty 14.04 (limited support)
* Ubuntu Precise 12.04 (limited support)
* Ubuntu Lucid 10.04 (limited support)


### OTHER REQUIREMENTS

* Wget must be installed.
* The outgoing TCP connections via ports: 25, 53, 80 and 443 must be open.
* Minimum 1 GB of RAM
* Locales with UTF-8 support, otherwise en_US.UTF-8 (default) is forced.
* Basic sysadmin skills and experience.
* Willingness to accept BOA PI (paranoid idiosyncrasies).


### PROVIDES

=== Included/enabled by default - see docs/NOTES.txt for details

* All libraries & tools required to install and run Nginx based Aegir system.
* Latest release of MariaDB 5.5 or 10.0 database server with Chive manager.
* Latest version of Nginx web server.
* SPDY Nginx support.
* PFS (Perfect Forward Secrecy) support in Nginx.
* PHP-FPM 5.6, 5.5, 5.4, 5.3 - multi-install mode, configurable per Octopus.
* PHP extensions: Zend OPcache, PHPRedis, UploadProgress, MailParse and ionCube.
* Fast Redis Cache with DB auto-failover for all 6.x and 7.x platforms.
* Fast Redis Lock support with DB auto-failover for all 6.x and 7.x platforms.
* Fast proxy DNS server (pdnsd) with permanent caching.
* Limited Shell, SFTP and FTPS separate accounts per Octopus instance.
* Limited Shell, SFTP and FTPS accounts per Aegir Client with per site access.
* Drush access on command line in all shell accounts.
* Drush Make access on command line for main shell account only.
* Support for New Relic monitoring with per Octopus instance license key.
* Solr 4 cores can be added/updated/deleted via site level INI settings.
* HTTPS access with self-signed certificate for all hosted sites.
* Magic Speed Booster cache, working like a Boost + AuthCache, but per user.
* Entry level XSS built-in protection on the Nginx level.
* Firewall csf/lfd integrated with Nginx abuse guard.
* PHP errors debugging, including WSOD, enabled on the fly on .dev. aliases.
* Boost, AdvAgg, Domain Access and Drupal for Facebook built-in support.
* Built-in collection of useful modules available in all platforms.
* Autonomous Maintenance & Auto-Healing scripts in /var/xdrago.
* Every 10 seconds uptime/self-healing local monitoring.
* Automated, rotated daily backups for all databases in /data/disk/arch/sql.

=== Optional add-ons - see docs/NOTES.txt for details

* Compass Tools.
* HHVM support - see docs/HHVM.txt for details.
* MultiCore Apache Solr 1.4.1 with Jetty 7 - see docs/SOLR.txt for details.
* MultiCore Apache Solr 3.6.2 with Jetty 8 - see docs/SOLR.txt for details.
* MultiCore Apache Solr 4.9.1 with Jetty 8 or Jetty 9 on Precise and Wheezy.
* New Relic Apps Monitor with per Octopus license and per Site reporting.
* Image Optimize toolkit binaries.
* FFmpeg support.
* Bind9 DNS server.
* Webmin Control Panel.
* SQL Buddy database manager.
* Collectd server monitor.
* LDAP Nginx support via third-party module (experimental).
* MongoDB driver for PHP (experimental).
* GEOS extension for PHP (all supported PHP versions).


### OCTOPUS PLATFORMS

Octopus can install the platforms listed below:

 @ Drupal 8.0.0

 Drupal 8.0.0-b7 -------------- https://drupal.org/drupal-8.0

 @ Drupal 7.37.1

 aGov 1.7 --------------------- https://drupal.org/project/agov
 Commerce 1.37 ---------------- https://drupal.org/project/commerce_kickstart
 Commerce 2.25 ---------------- https://drupal.org/project/commerce_kickstart
 Commons 3.26 ----------------- https://drupal.org/project/commons
 Drupal 7.37.1 ---------------- https://drupal.org/drupal-7.37
 ERPAL 2.2 -------------------- https://drupal.org/project/erpal
 Guardr 2.14 ------------------ https://drupal.org/project/guardr
 OpenAcademy 1.1 -------------- https://drupal.org/project/openacademy
 OpenAid 2.1 ------------------ https://drupal.org/project/openaid
 OpenAtrium 2.41 -------------- https://drupal.org/project/openatrium
 OpenBlog 1.0-v3 -------------- https://drupal.org/project/openblog
 OpenChurch 1.17-b2 ----------- https://drupal.org/project/openchurch
 OpenChurch 2.1-b7 ------------ https://drupal.org/project/openchurch
 OpenDeals 1.35 --------------- https://drupal.org/project/opendeals
 OpenOutreach 1.20 ------------ https://drupal.org/project/openoutreach
 OpenPublic 1.5 --------------- https://drupal.org/project/openpublic
 OpenScholar 3.20.0 ----------- http://theopenscholar.org
 Panopoly 1.22 ---------------- https://drupal.org/project/panopoly
 Recruiter 1.6 ---------------- https://drupal.org/project/recruiter
 Restaurant 1.0-b12 ----------- https://drupal.org/project/restaurant
 Ubercart 3.8 ----------------- https://drupal.org/project/ubercart

 @ Pressflow 6.35.1

 Commons 2.24 ----------------- https://drupal.org/project/commons
 Feature Server 1.2 ----------- http://bit.ly/fserver
 Pressflow 6.35.1 ------------- http://pressflow.org
 Ubercart 2.14 ---------------- https://drupal.org/project/ubercart

* All D7 platforms have been enhanced using Drupal 7.37.1 +Extra core:
  https://github.com/omega8cc/7x/tree/7.x-om8

* All D6 platforms have been enhanced using Pressflow 6.35.1 +Extra core:
  https://github.com/omega8cc/pressflow6/tree/pressflow-plus

* All D6 and D7 platforms include some useful and/all performance related
  contrib modules - see docs/MODULES.txt for details.

