
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
### For complete installation instructions see docs/INSTALL.txt
### For the upgrade instructions see docs/UPGRADE.txt
### For recipe on local working install see docs/HINTS.txt
### For how-to on using MultiCore Solr Tomcat see docs/SOLR.txt
###
###--------------------------------------------------------------###


Barracuda will be still the main script for base system
install and upgrades, including main Aegir instance,
but no platforms will be added there to keep it compatible
with all existing and future installs, when you don't need
any ready to use platforms and instead you are using the system
for managing your own imported platforms/sites.

Octopus will be Aegir + Platforms installer (you will be able
to interactively choose the platforms you wish to install)
and updater only and will allow to install new versions
of platforms with clean directory structure, with code shared
between all created sub-instances, so one vanilla instance
will use only ~18MB, while most of the code, which is over
330MB total, will be shared.

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

* Ubuntu Lucid 10.04 minimal OS fresh install, or
* Ubuntu Karmic 9.10 minimal OS fresh install, or
* Debian 5.0 Lenny minimal OS fresh install.


### PROVIDES

* All libraries & tools required to install and run Nginx based Aegir system.
* Latest version of MariaDB database server.
* Latest version of Nginx web server with upload progress and Boost support.
* PHP-FPM 5.2.14 with APC, memcache, uploadprogress, suhosin and ionCube.
* Maintenance & Auto-Healing scripts in /var/xdrago.
* Automated, rotated daily backups for all databases in /data/disk/arch/sql.
* MultiCore Apache Solr with Tomcat.
* Redis and Memcached chained cache with DB failover.
* Chive database manager in "db." subdomain.
* Collectd server monitor in "cgp." subdomain.
* Limited shell and FTPS separate accounts per Octopus instance.


### HELP

* See: http://groups.drupal.org/nginx


### MAINTAINERS

* Grace  - http://omega8.cc
* Albert - http://omega8.cc
* Matt   - http://omega8.cc


### CREDITS

* Brian Mercer - http://drupal.org/user/103565
  Initial work: http://drupal.org/node/244072#comment-1747170

* Nice people who are submitting bugs and problems in the
  GitHub issue queue.

