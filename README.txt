
### README

All-in-one bash scripts (see BARRACUDA.sh.txt and OCTOPUS.sh.txt)
to install and/or upgrade Aegir Hosting Systems for Drupal.


###--------------------------------------------------------------###
### IMPORTANT: run it as root (not via sudo!) with bash, not sh  ###
###--------------------------------------------------------------###
###
### $ bash BARRACUDA.sh.txt
### $ bash OCTOPUS.sh.txt
###
### Please read all comments for configuration options in both
### installers, since there is information not included in the
### README or INSTALL and can be modified/updated with every
### new Edition.
###
### For basic installation instructions see docs/INSTALL.txt
### For the upgrade instructions see docs/UPGRADE.txt
### For recipe on local working install see docs/HINTS.txt
### For how-to on using MultiCore Solr Tomcat see docs/SOLR.txt
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
while most of the code, which is almost 400 MB total, is shared.

With multi-install system you have to remember that all of them
will use the same Nginx server, so you could break the system
trying to install site with the same domain on two or more instances.
The instances will not be aware of other running instances,
so it is your responsibility to use such system wisely.

There is also Tuner script available (see BOND.sh.txt) for easy
system tuning for development and switching it back easily to the
standard production settings.


### REQUIREMENTS

* Debian 6.0 Squeeze (recommended) minimal OS 32/64bit fresh install, or
* Debian 5.0 Lenny minimal OS 32/64bit fresh install, or
* Ubuntu Oneiric 11.10 minimal OS 32/64bit fresh install, or
* Ubuntu Natty 11.04 minimal OS 32/64bit fresh install, or
* Ubuntu Maverick 10.10 minimal OS 32/64bit fresh install, or
* Ubuntu Lucid 10.04 minimal OS 32/64bit fresh install, or
* Ubuntu Karmic 9.10 minimal OS 32/64bit fresh install, or
* Jolicloud Robby for netbooks fresh or existing install.
* The Git standard port 9418 must be open.
* Minimum 512 MB of RAM or minimum 2 GB of RAM with Solr/Tomcat enabled.
* Basic sysadmin skills and experience.


### PROVIDES

* All libraries & tools required to install and run Nginx based Aegir system.
* Latest release of MariaDB 5.2 or Percona 5.5 database server.
* Latest version of Nginx web server with upload progress and Boost support.
* PHP-FPM 5.2.17 with APC, memcached, uploadprogress, suhosin and ionCube.
* Maintenance & Auto-Healing scripts in /var/xdrago.
* Automated, rotated daily backups for all databases in /data/disk/arch/sql.
* MultiCore Apache Solr with Tomcat (optional).
* Redis and Memcached chained cache with DB auto-failover.
* Fast proxy DNS server (pdnsd) with permanent caching.
* Bind9 DNS server integrated with experimental Aegir DNS feature (optional).
* Webmin Control Panel (optional).
* Firewall csf/lfd integrated with Nginx abuse guard (optional).
* Chive database manager in "chive." subdomain (optional).
* SQL Buddy database manager in "sqlbuddy." subdomain (optional).
* Collectd server monitor in "cgp." subdomain (optional).
* Limited shell and FTPS separate accounts per Octopus instance.


### OCTOPUS PLATFORMS

Octopus can install the platforms listed below:

 Acquia 6.22 (int) ------------ http://bit.ly/acquiadrupal
 Acquia 7.9.8 ----------------- http://bit.ly/acquiadrupal
 Acquia Commons 2.2 ----------- http://acquia.com/drupalcommons
 CiviCRM 3.4.7 ---------------- http://civicrm.org
 CiviCRM 4.0.7 ---------------- http://civicrm.org
 Commerce Kickstart 1.0-rc4 --- http://drupalcommerce.org
 Conference 1.0-beta2 --------- http://usecod.com
 Drupal 5.23 Pressflow -------- http://pressflow.org
 Drupal 6.22 Pressflow (int) -- http://pressflow.org
 Drupal 7.9 ------------------- http://drupal.org/drupal-7.0
 Feature Server --------------- http://bit.ly/fserver
 Managing News 1.2 ------------ http://managingnews.com
 NodeStream 1.0 --------------- http://nodestream.org
 Open Atrium 1.0 -------------- http://openatrium.com
 Open Enterprise 1.0-beta3 ---- http://leveltendesign.com/enterprise
 OpenChurch 1.21 -------------- http://openchurchsite.com
 OpenPublic 1.0-beta3 --------- http://openpublicapp.com
 OpenScholar 2.0-beta11 ------- http://openscholar.harvard.edu
 ProsePoint 0.40 6.22 --------- http://prosepoint.org
 Ubercart 6.x-2.7 (int) ------- http://ubercart.org
 Videola 1.0-alpha1 ----------- http://videola.tv

All 5/6 platforms have been enhanced using Pressflow Drupal core.

Platforms marked with (int) comes also with ready to use translations
of Drupal core in 25 languages. Only languages with at least 10 maintainers
and at least 60% of progress are included - http://localize.drupal.org

Other platforms are using extended and customized translations or
require far more than just core translation, so we don't touch them.

There are also some useful and/or performance related modules
added to all 6.x platforms:

 admin-6.x-2.0
 backup_migrate-6.x-2.4
 blockcache_alter-6.x-1.x-dev
 boost-6.x-1.x-dev
 cache-6.x-1.x-dev
 config_perms-6.x-2.x-dev
 css_emimage-6.x-2.x-dev
 dbtuner-6.x-1.x-dev
 filefield_nginx_progress-6.x-1.4
 fpa-6.x-2.3
 httprl-6.x-1.2
 imageinfo_cache-6.x-2.0
 login_security-6.x-1.x-dev
 private_upload-6.x-1.x-dev
 readonlymode-6.x-1.x-dev
 robotstxt-6.x-1.x-dev
 seckit-6.x-1.3
 securesite-6.x-2.4
 site_verify-6.x-1.0
 textile-6.x-2.4
 variable_clean-6.x-1.x-dev
 views_content_cache-6.x-2.x-dev
 views404-6.x-1.x-dev
 + theme rubik-6.x-3.0-beta2

The Drupal 7.x platforms come with contrib modules:

 admin-7.x-2.0-beta3
 agrcache-7.x-1.0
 backup_migrate-7.x-2.2
 blockcache_alter-7.x-1.x-dev
 boost-7.x-1.x-dev
 config_perms-7.x-2.x-dev
 core_library-7.x-2.0-alpha7
 css_emimage-7.x-1.2
 filefield_nginx_progress-7.x-1.x-dev
 flood_control-7.x-1.x-dev
 fpa-7.x-2.0
 httprl-7.x-1.2
 readonlymode-7.x-1.0-beta1
 robotstxt-7.x-1.x-dev
 seckit-7.x-1.3
 site_verify-7.x-1.0
 textile-7.x-2.0-rc9
 variable_clean-7.x-1.x-dev
 vars-7.x-2.0-alpha10
 + theme rubik-7.x-4.0-beta6


### BUG SUBMISSION

* Please follow bug submission guidelines:

  Before you submit a bug, make sure you have diagnosed your
  configuration as documented in this guide:
  http://groups.drupal.org/node/21890. It is Aegir specific,
  but the good rules are the same: always search for similar
  bug report before submitting your own, and include as much
  information about your context as possible, especially
  please include, using http://gist.github.com, the contents
  of files:

    /var/aegir/config/includes/barracuda_log.txt
    /data/disk/user/log/octopus_log.txt
    /var/aegir/install.log (remove the password)

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

