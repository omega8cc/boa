
### README

All-in-one bash scripts (see docs/INSTALL.txt for details)
to install and/or upgrade high performance Aegir Hosting Systems
for Drupal, with Nginx, PHP-FPM, MariaDB/Percona and Redis,
now available with simple command line tools: http://bit.ly/JHpFSh


###--------------------------------------------------------------###
###
### For BOA installation instructions see docs/INSTALL.txt
### See also related information in docs/NOTES.txt
### For BOA upgrade instructions see docs/UPGRADE.txt
### For how-to on using MultiCore Solr Jetty see docs/SOLR.txt
### For custom Nginx rewrites how-to see docs/HINTS.txt
### For SSL and extra IPs how-to see docs/SSL.txt
### For sites migration between instances see docs/REMOTE.txt
###
### Please read all comments for configuration options in both
### BARRACUDA.sh.txt and OCTOPUS.sh.txt, since there is information
### not included in the README or INSTALL and can be modified or
### updated with every new Edition.
###
###--------------------------------------------------------------###


You can install one Aegir Master Instance on your server using
Barracuda and any number of Aegir Satellite Instances using
Octopus installer.

Note: the 'Master' and 'Satellite' names in the Barracuda/Octopus
context are not related to the multi-server Aegir features.
It is related to the multi-Aegir-instances environment, with
virtual chroot/jail for every Aegir instance.

Barracuda is the main script for the Aegir Master Instance system
install and upgrades, including OS env and main Aegir instance,
but no platforms will be added there to keep it compatible
with all existing and future installs, when you don't need
any ready to use platforms and instead you are using the system
for managing your own imported platforms/sites.

Octopus is an Aegir + Platforms installer (you can interactively
choose the platforms you wish to install on the instance)
and updater only. It allows to install new versions of platforms
with clean directory structure, with code shared between all created
instances, so one vanilla Octopus instance is using only ~18 MB,
while most of the code, which is over 1700 MB total, is shared.

Sharing the code between instances is of critical importance,
because it allows you to dramatically lower RAM and CPU usage,
because most of the actively used code is opcode cached.

With multi-install system you have to remember that all of them
will use the same Nginx server, so you could break the system
trying to install site with the same domain on two or more instances.
The instances will not be aware of other running instances,
so it is your responsibility to use such system wisely.

There is also Tuner script available (see aegir/tools/BOND.sh.txt)
for easy system tuning for development and switching it back easily
to the standard production settings.


### SUPPORTED PARENT SYSTEMS

* Xen, VServer, Linux KVM or VMware based VPS or a dedicated box.
* VirtualBox VM for localhost install - check the how-to for:
  Ubuntu Precise desktop image install: http://bit.ly/boa-precise
  Debian Squeeze desktop image install: http://bit.ly/boa-squeeze


### SUPPORTED LTS OS 32/64bit - Minimal on server or Desktop on localhost

* Debian 7 Wheezy (recommended)
* Debian 6 Squeeze (fully supported) (automatic upgrade to Wheezy supported)
* Ubuntu Precise 12.04 (very limited support)
* Ubuntu Lucid 10.04 (very limited support)

NOTE: BOA maintainers currently use Debian 6 Squeeze, but for new installs
      we recommend Debian 7 Wheezy. We don't use and rarely test Ubuntu,
      so if you have any good reason to use Ubuntu, don't blame us
      if it will not survive next upgrade. We are trying to include it as
      (barely) supported OS only for those who can't use Debian because of
      company or organization policy etc. But we strongly suggest to avoid
      Ubuntu and instead use Debian, wherever possible, for best results.


### PREVIOUSLY SUPPORTED OS (deprecated)

* Debian 5.0 Lenny (automatic upgrade to Squeeze supported)
* Ubuntu Oneiric 11.10
* Ubuntu Natty 11.04
* Ubuntu Maverick 10.10
* Ubuntu Karmic 9.10
* Jolicloud Robby


### OTHER REQUIREMENTS

* Wget must be installed.
* The Git standard port 9418 must be open.
* SMTP standard port 25 (or SMTP relay) must be open for outgoing connections.
* Minimum 512 MB of RAM (1 GB for heavy distros, like Atrium 2, Commerce etc.)
* Locales with UTF-8 support, otherwise en_US.UTF-8 (default) is forced.
* Basic sysadmin skills and experience.


### PROVIDES

=== Included by default - see docs/NOTES.txt for details

* All libraries & tools required to install and run Nginx based Aegir system.
* Latest release of MariaDB 5.5 database server with Chive manager.
* Latest version of Nginx web server.
* PHP-FPM 5.5, 5.4, 5.3 - multi-install mode, configured per Octopus instance.
* PHP extensions: Zend OPcache, PHPRedis, UploadProgress, MailParse and ionCube.
* Fast Redis Cache with DB auto-failover for all 6.x and 7.x platforms.
* Fast proxy DNS server (pdnsd) with permanent caching.
* Limited Shell, SFTP and FTPS separate accounts per Octopus instance.
* Limited Shell, SFTP and FTPS accounts per Aegir Client with per site access.
* Drush and Drush Make access - drush4, drush6 and drush7 on command line.
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

* MultiCore Apache Solr 1.4.1 with Jetty 7 - see docs/SOLR.txt for details.
* MultiCore Apache Solr 3.6.2 with Jetty 8 - see docs/SOLR.txt for details.
* MultiCore Apache Solr 4.2.0 with Jetty 8 or Jetty 9 on Precise and Wheezy.
* Fast Redis Lock support with DB auto-failover for all 6.x and 7.x platforms.
* Latest release of Percona 5.5 database server.
* New Relic Server and Apps Monitor with per Site/Instance/Server reporting.
* LDAP Nginx support via third-party module.
* SPDY Nginx support.
* PFS (Perfect Forward Secrecy) support in Nginx.
* MongoDB driver for PHP 5.3
* GEOS extension for PHP 5.3 (experimental).
* FFmpeg support.
* Bind9 DNS server.
* Webmin Control Panel.
* SQL Buddy database manager.
* Collectd server monitor.
* Compass Tools.


### OCTOPUS PLATFORMS

Octopus can install the platforms listed below:

### Drupal 7.25.1

 Commerce 1.21 ---------------- http://drupal.org/project/commerce_kickstart
 Commerce 2.11 ---------------- http://drupal.org/project/commerce_kickstart
 Commons 3.6 ------------------ http://drupal.org/project/commons
 Drupal 7.25.1 ---------------- http://drupal.org/drupal-7.25
 Open Academy 1.0-rc3 --------- http://drupal.org/project/openacademy
 Open Atrium 2.12 ------------- http://drupal.org/project/openatrium
 Open Deals 1.31 -------------- http://drupal.org/project/opendeals
 Open Outreach 1.3 ------------ http://drupal.org/project/openoutreach
 OpenBlog 1.0-a3 -------------- http://drupal.org/project/openblog
 OpenChurch 1.11-b15 ---------- http://drupal.org/project/openchurch
 OpenScholar 3.9.3 ------------ http://theopenscholar.org
 Panopoly 1.0-rc5 ------------- http://drupal.org/project/panopoly
 Recruiter 1.1.2 -------------- http://drupal.org/project/recruiter
 Spark 1.0-a10 ---------------- http://drupal.org/project/spark
 Totem 1.1.2 ------------------ http://drupal.org/project/totem
 Ubercart 3.6.0 --------------- http://drupal.org/project/ubercart

### Pressflow 6.29.1

 Commons 2.14.0 --------------- http://drupal.org/project/commons
 Feature Server 1.2 ----------- http://bit.ly/fserver
 Managing News 1.2.4 ---------- http://drupal.org/project/managingnews
 Open Atrium 1.7.2 ------------ http://drupal.org/project/openatrium
 Pressflow 6.29.1 ------------- http://pressflow.org
 Ubercart 2.13.0 -------------- http://drupal.org/project/ubercart

All D7 platforms have been enhanced using Drupal 7.25.1 +Extra core:
https://github.com/omega8cc/7x/tree/7.x-om8

All D6 platforms have been enhanced using Pressflow 6.29.1 +Extra core:
https://github.com/omega8cc/pressflow6/tree/pressflow-plus


### BUG SUBMISSION

* Please follow bug submission guidelines:

  Before you submit a bug, make sure you have diagnosed your
  configuration as documented in this guide:
  http://groups.drupal.org/node/21890. It is Aegir specific,
  but the good rules are the same: always search for similar
  bug report before submitting your own, and include as much
  information about your context as possible, especially
  please include, using http://gist.github.com, the contents
  (anonymized for security and privacy) of files:

    /root/.barracuda.cnf
    /var/log/barracuda_log.txt
    /root/.USER.octopus.cnf
    /data/disk/USER/log/octopus_log.txt

* Issue queues:
  http://drupal.org/project/issues/barracuda (active)
  http://drupal.org/project/issues/octopus (active)
  http://github.com/omega8cc/nginx-for-drupal/issues (deprecated)

  Please don't post your server logs here. Instead use
  http://gist.github.com and post the link in your submission.


### HELP

* Join us at: http://groups.drupal.org/boa
              http://community.aegirproject.org
              http://groups.drupal.org/nginx


### MAINTAINERS

* Grace  - http://omega8.cc
* Albert - http://omega8.cc
* Robert - http://omega8.cc


### REPOSITORIES

* http://drupal.org/project/barracuda (main)
* http://drupal.org/project/octopus (main)
* http://code.aegir.cc/aegir (mirror)
* http://github.com/omega8cc/nginx-for-drupal/ (mirror)


### CREDITS

* Brian Mercer - http://drupal.org/user/103565
  Initial work: http://drupal.org/node/244072#comment-1747170

* Nice people who are submitting bugs and problems in the
  Barracuda/Octopus issue queues.

