
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


Barracuda is the main script for the base/core Aegir Hosting System
install and upgrades, including OS env, main Aegir instance,
but no platforms will be added there to keep it compatible
with all existing and future installs, when you don't need
any ready to use platforms and instead you are using the system
for managing your own imported platforms/sites.

Octopus is an Aegir + Platforms installer (you can interactively
choose the platforms you wish to install on the instance)
and updater only. It allows to install new versions of platforms
with clean directory structure, with code shared between all created
instances, so one vanilla Octopus instance is using only ~18 MB,
while most of the code, which is over 450 MB total, is shared.

Both Barracuda and Octopus don't use Pressflow for Aegir itself
to avoid possible issues. There is no visible benefits to use
faster core for Aegir itself, however we used it before with
good results and who knows, maybe we will introduce it again.

With multi-install system you have to remember that all of them
will use the same Nginx server, so you could break the system
trying to install site with the same domain on two or more instances.
The instances will not be aware of other running instances,
so it is your responsibility to use such system wisely.


### REQUIREMENTS

* Ubuntu Lucid 10.04 minimal OS 32/64bit fresh install, or
* Ubuntu Karmic 9.10 minimal OS 32/64bit fresh install, or
* Jolicloud Robby for netbooks fresh or existing install, or
* Debian 5.0 Lenny minimal OS 32/64bit fresh install.
* The Git standard port 9418 must be open.
* 512 MB of RAM or at least 1 GB of RAM for OpenPublish.


### PROVIDES

* All libraries & tools required to install and run Nginx based Aegir system.
* Latest version of MariaDB database server.
* Latest version of Nginx web server with upload progress and Boost support.
* PHP-FPM 5.2.16 with APC, memcache, uploadprogress, suhosin and ionCube.
* Maintenance & Auto-Healing scripts in /var/xdrago.
* Automated, rotated daily backups for all databases in /data/disk/arch/sql.
* MultiCore Apache Solr with Tomcat.
* Redis and Memcached chained cache with DB failover.
* Fast proxy DNS server (pdnsd) with permanent caching.
* Bind9 DNS server integrated with experimental Aegir DNS feature.
* Webmin Control Panel.
* Chive database manager in "chive." subdomain.
* SQL Buddy database manager in "sqlbuddy." subdomain.
* Collectd server monitor in "cgp." subdomain.
* Limited shell and FTPS separate accounts per Octopus instance.


### OCTOPUS PLATFORMS

Octopus can install the platforms listed below:

 Atrium 1.0-beta8 ------------- http://openatrium.com
 Managing News 1.2 ------------ http://managingnews.com
 Drupal Commons 1.1 ----------- http://acquia.com/drupalcommons
 Acquia 6.20-svn (int) -------- http://bit.ly/acquiadrupal
 OpenPublish 2.3.432 ---------- http://openpublishapp.com
 OpenScholar 2.0-b8-3.1 ------- http://openscholar.harvard.edu
 ProsePoint 0.37 (int) -------- http://prosepoint.org
 Ubercart (int) --------------- http://ubercart.org
 Drupal 5.23 Pressflow -------- http://pressflow.org
 Drupal 6.20 Pressflow (int) -- http://pressflow.org
 Drupal 6.20 Cocomore --------- http://drupal.cocomore.com
 Drupal 7.0-rc4 --------------- http://drupal.org/project/drupal
 Feature Server --------------- http://bit.ly/fserver
                                http://bit.ly/fservermore

All 5/6 platforms have been enhanced using Pressflow Drupal core.

Platforms marked with (int) comes also with ready to use translations
of Drupal core in 22 languages. Only languages with at least 10 maintainers
and at least 60% of progress are included - http://localize.drupal.org

Other platforms are using extended and customized translations or
require far more than just core translation, so we don't touch them.

There are also some useful and/or performance related modules
added to all 6.x platforms:

 cache-6.x-1.x-dev
 boost-6.x-1.x-dev
 dbtuner-6.x-1.x-dev
 expire-6.x-1.x-dev
 elysia_cron-6.x-1.x-dev
 session_expire-6.x-1.x-dev
 javascript_aggregator-6.x-1.x-dev
 css_emimage-6.x-2.x-dev
 views_content_cache-6.x-2.x-dev
 views404-6.x-1.x-dev
 filefield_nginx_progress-6.x-1.4
 securesite-6.x-2.4
 session443-6.x-1.x-dev
 backup_migrate-6.x-2.x-dev
 openidadmin-6.x-1.2
 site_verify-6.x-1.x-dev


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
  
* Issue queue:
  http://github.com/omega8cc/nginx-for-drupal/issues
  
  Please don't post your server logs here. Instead use
  http://gist.github.com and post the link in your submission.
  

### HELP

* Join us at: http://community.aegirproject.org
              http://groups.drupal.org/nginx


### MAINTAINERS

* Grace  - http://omega8.cc
* Albert - http://omega8.cc


### CREDITS

* Brian Mercer - http://drupal.org/user/103565
  Initial work: http://drupal.org/node/244072#comment-1747170

* Nice people who are submitting bugs and problems in the
  GitHub issue queue.

