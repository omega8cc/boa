
### README

BOA is an acronym of high performance Barracuda, Octopus and Aegir LEMP stack.

Includes all-in-one bash scripts (see docs/INSTALL.txt for details) to install
and upgrade high performance Aegir Hosting Systems for Drupal, with Nginx,
PHP-FPM, Zend OPcache, MariaDB and Redis.


###--------------------------------------------------------------------------###
###
### For BOA installation instructions see docs/INSTALL.txt
### See also related information in docs/NOTES.txt
### For BOA upgrade instructions see docs/UPGRADE.txt
###
### Barracuda configuration template ..: docs/cnf/barracuda.cnf
### Octopus configuration template ....: docs/cnf/octopus.cnf
### System control files index ........: docs/ctrl/system.ctrl
###
### Please read all comments for configuration options in both
### BARRACUDA.sh.txt and OCTOPUS.sh.txt, since there is information
### not included in the README or INSTALL and can be modified or
### updated with every new Edition.
###
### Platform and site level INI templates:
###
###   aegir/conf/default.boa_platform_control.ini
###   aegir/conf/default.boa_site_control.ini
###
### Octopus platforms configuration symbols: docs/PLATFORMS.txt
###
### Modules - supported, enabled or disabled: docs/MODULES.txt
###
### For how-to on using MultiCore Solr Jetty see docs/SOLR.txt
### For custom Nginx rewrites how-to see docs/HINTS.txt
### For SSL and extra IPs how-to see docs/SSL.txt
### For sites migration between instances see docs/REMOTE.txt
### For advanced password encryption tips see: docs/BLOWFISH.txt
### For security related settings see: docs/SECURITY.txt
### For frequently asked questions and answers see docs/FAQ.txt
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
only ~18 MB, while most of the code, which is over 1 GB total, is shared.

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


### SUPPORTED PARENT SYSTEMS

* Xen, VServer, Linux KVM or VMware based VPS or a dedicated box.

* VirtualBox VM for localhost install - check the (old) how-to for:
  Ubuntu Precise desktop image install: http://bit.ly/boa-precise
  Debian Squeeze desktop image install: http://bit.ly/boa-squeeze

NOTE: BOA maintainers use only server (public) install mode and rarely test
      localhost (local) mode, which is considered highly experimental,
      while server (public) mode is considered stable and fully supported.


### SUPPORTED LTS OS 32/64bit - Minimal on server or Desktop on localhost

* Debian 7 Wheezy (recommended)
* Debian 6 Squeeze (fully supported with automatic upgrade to Wheezy available)
* Ubuntu Trusty 14.04 (limited support)
* Ubuntu Precise 12.04 (limited support)
* Ubuntu Lucid 10.04 (limited support)

NOTE: BOA maintainers currently use only Debian based 64bit systems/servers.
      We don't use and rarely test Ubuntu, so for best results use Debian 64bit.


### OTHER REQUIREMENTS

* Wget must be installed.
* The Git standard port 9418 must be open.
* SMTP standard port 25 (or SMTP relay) must be open for outgoing connections.
* Minimum 1 GB of RAM
* Locales with UTF-8 support, otherwise en_US.UTF-8 (default) is forced.
* Basic sysadmin skills and experience.
* Willingness to accept BOA PI (paranoid idiosyncrasies).


### PROVIDES

=== Included by default - see docs/NOTES.txt for details

* All libraries & tools required to install and run Nginx based Aegir system.
* Latest release of MariaDB 5.5 or 10.0 database server with Chive manager.
* Latest version of Nginx web server.
* PHP-FPM 5.5, 5.4, 5.3 - multi-install mode, configurable per Octopus instance.
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
* PHP errors debugging, including WSOD, enabled on the fly on dev. aliases.
* Boost, AdvAgg, Domain Access and Drupal for Facebook built-in support.
* Built-in collection of useful modules available in all platforms.
* Autonomous Maintenance & Auto-Healing scripts in /var/xdrago.
* Every 10 seconds uptime/self-healing local monitoring.
* Automated, rotated daily backups for all databases in /data/disk/arch/sql.

=== Optional add-ons - see docs/NOTES.txt for details

* Compass Tools.
* SPDY Nginx support.
* PFS (Perfect Forward Secrecy) support in Nginx.
* MultiCore Apache Solr 1.4.1 with Jetty 7 - see docs/SOLR.txt for details.
* MultiCore Apache Solr 3.6.2 with Jetty 8 - see docs/SOLR.txt for details.
* MultiCore Apache Solr 4.2.0 with Jetty 8 or Jetty 9 on Precise and Wheezy.
* New Relic Apps Monitor with per Octopus license and per Site reporting.
* Image Optimize toolkit binaries.
* FFmpeg support.
* Bind9 DNS server.
* Webmin Control Panel.
* SQL Buddy database manager.
* Collectd server monitor.
* LDAP Nginx support via third-party module (experimental).
* MongoDB driver for PHP 5.3 (experimental).
* GEOS extension for PHP 5.3 (experimental).


### OCTOPUS PLATFORMS

Octopus can install the platforms listed below:

 @ Drupal 7.32.1

 aGov 1.5 --------------------- https://drupal.org/project/agov
 Commerce 1.31 ---------------- https://drupal.org/project/commerce_kickstart
 Commerce 2.19 ---------------- https://drupal.org/project/commerce_kickstart
 Commons 3.17 ----------------- https://drupal.org/project/commons
 Drupal 7.32.1 ---------------- https://drupal.org/drupal-7.32
 ERPAL 2.1 -------------------- https://drupal.org/project/erpal
 Guardr 1.14 ------------------ https://drupal.org/project/guardr
 Open Academy 1.1 ------------- https://drupal.org/project/openacademy
 Open Atrium 2.22 ------------- https://drupal.org/project/openatrium
 Open Deals 1.33 -------------- https://drupal.org/project/opendeals
 Open Outreach 1.12 ----------- https://drupal.org/project/openoutreach
 OpenBlog 1.0-v3 -------------- https://drupal.org/project/openblog
 OpenChurch 1.14 -------------- https://drupal.org/project/openchurch
 OpenChurch 2.0-b1 ------------ https://drupal.org/project/openchurch
 OpenPublic 1.2 --------------- https://drupal.org/project/openpublic
 OpenScholar 3.15.1 ----------- http://theopenscholar.org
 Panopoly 1.12 ---------------- https://drupal.org/project/panopoly
 Recruiter 1.3 ---------------- https://drupal.org/project/recruiter
 Restaurant 1.0-b9 ------------ https://drupal.org/project/restaurant
 Spark 1.0-b1 ----------------- https://drupal.org/project/spark
 Totem 1.1.2 ------------------ https://drupal.org/project/totem
 Ubercart 3.7 ----------------- https://drupal.org/project/ubercart

 @ Pressflow 6.33.1

 Commons 2.20 ----------------- https://drupal.org/project/commons
 Feature Server 1.2 ----------- http://bit.ly/fserver
 Managing News 1.2.4 ---------- https://drupal.org/project/managingnews
 Open Atrium 1.7.2 ------------ https://drupal.org/project/openatrium
 Pressflow 6.33.1 ------------- http://pressflow.org
 Ubercart 2.13 ---------------- https://drupal.org/project/ubercart

* All D7 platforms have been enhanced using Drupal 7.32.1 +Extra core:
  https://github.com/omega8cc/7x/tree/7.x-om8

* All D6 platforms have been enhanced using Pressflow 6.33.1 +Extra core:
  https://github.com/omega8cc/pressflow6/tree/pressflow-plus

* All D6 and D7 platforms include some useful and/all performance related
  contrib modules - see docs/MODULES.txt for details.


### BUG SUBMISSION

* Active issue queue ---------- https://github.com/omega8cc/boa/issues

Reporting bugs is a great way to contribute to BOA. Mis-reporting bugs or
duplicating reports, however, can be a distraction to the development team
and waste precious resources. So, help out by following these guidelines.

!!! Any bug report failing to follow the guidelines will be ignored and closed.

Before reporting a bug always search for similar bug report before submitting
your own, and include as much information about your context as possible,
including your server/VPS parent system name (like Xen) and/or hosting provider
name and URL. Especially please attach the contents (anonymized for security
and privacy) of files listed below.

  /root/.barracuda.cnf
  /var/log/barracuda_log.txt
  /root/.USER.octopus.cnf
  /data/disk/USER/log/octopus_log.txt

!!! Don't post your server or error logs in the issue directly. Instead use
!!! services like http://gist.github.com and post the link in your submission.

HINT: Please enable debugging with _DEBUG_MODE=YES in the /root/.barracuda.cnf
      file before running upgrade, so it will display more helpful details.
      You can find more verbose logs in the /var/backups/ directory.

It is also a good idea to search first our deprecated issue queues for
Barracuda and Octopus projects on drupal.org:

* Legacy issue queue ---------- https://drupal.org/project/issues/barracuda
* Legacy issue queue ---------- https://drupal.org/project/issues/octopus


### HELP OPTIONS

* Docs and How-to ------------- https://omega8.cc/library/development
* Community IRC channel ------- irc://irc.freenode.net/omega8cc
* Commercial support ---------- https://omega8.cc


### MAINTAINERS

BOA development is maintained and sponsored by Omega8.cc

  https://omega8.cc/about


### CREDITS

* Brian Mercer ---------------- https://drupal.org/user/103565
  Initial work ---------------- https://drupal.org/node/244072#comment-1747170

* Nice people who are submitting bugs and problems in the issue queue.


### DONATIONS

If you wish to support BOA development or simply send a nice 'Thank you'
to the Universe, please donate something to The Rights of the Child charity:

  http://trotc.org/

Thank you!

