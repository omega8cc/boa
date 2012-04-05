
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

* Xen, VServer or VMware based VPS or a dedicated box. Avoid Virtuozzo/OpenVZ.
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
* Latest release of MariaDB 5.3 or Percona 5.5 database server.
* Latest version of Nginx web server with upload progress and Boost support.
* PHP-FPM 5.3.10 with APC, phpredis, uploadprogress, suhosin and ionCube.
* PHP-FPM 5.2.17 with APC, phpredis, uploadprogress, suhosin and ionCube.
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

 Acquia 6.25.1 (int) ---------- http://bit.ly/acquiadrupal
 Acquia Commons 2.6 ----------- http://acquia.com/drupalcommons
 CiviCRM 3.4.8-d6 ------------- http://civicrm.org
 CiviCRM 4.0.8-d7 ------------- http://civicrm.org
 Commerce Kickstart 1.4 ------- http://drupalcommerce.org
 Conference 1.0-beta2 --------- http://usecod.com
 Drupal 7.12 ------------------ http://drupal.org/drupal-7.12
 Drupal 8.0-dev --------------- http://bit.ly/drupal-eight
 ELMS 1.0-alpha6 -------------- http://elms.psu.edu
 Feature Server --------------- http://bit.ly/fserver
 Managing News 1.2.1 ---------- http://managingnews.com
 MartPlug 1.0-dev ------------- http://drupal.org/project/martplug
 NodeStream 1.4 --------------- http://nodestream.org
 NodeStream 2.0-alpha10 ------- http://nodestream.org
 Octopus Video 1.0-alpha5 ----- http://octopusvideo.org
 Open Atrium 1.3.1 ------------ http://openatrium.com
 Open Deals 1.0-beta7 --------- http://opendealsapp.com
 Open Outreach 1.0-beta8 ------ http://openoutreach.org
 OpenChurch 1.9-alpha3 -------- http://openchurchsite.com
 OpenPublic 1.0-beta3 --------- http://openpublicapp.com
 OpenPublish 3.0-alpha7 ------- http://openpublishapp.com
 OpenScholar 2.0-beta13 ------- http://openscholar.harvard.edu
 Pressflow 5.23 --------------- http://pressflow.org
 Pressflow 6.25.1 (int) ------- http://pressflow.org
 ProsePoint 0.43 -------------- http://prosepoint.org
 Ubercart 2.7.1 (int) --------- http://ubercart.org
 Ubercart 3.0.3 --------------- http://ubercart.org
 Videola 1.0-alpha2 ----------- http://videola.tv

All 5/6 platforms have been enhanced using Pressflow Drupal core.

Platforms marked with (int) come also with ready to use translations
of Drupal core in 25 languages. Only languages with at least
10 maintainers and at least 60% of progress are included.
Other platforms are using extended and customized translations or
require far more than just core translation, so we don't touch them.

There are also some useful and/or performance related modules
added to all 6.x and 7.x platforms and you can review the full list
with currently used versions/releases at our website:

 http://omega8.cc/extra-modules-available-in-all-platforms-123

Some core and contrib modules are either enabled or disabled
by default, by running daily (at morning) maintenance monitor.

There are also modules supported by Octopus, but not bundled
by default and/or not enabled.

Some modules require custom rewrites on the web server level,
but since there is no .htaccess available/used in Nginx,
we have added all required rewrites and associated supported
configuration settings on the system level. This is the real
meaning of [S]upported flag here.

Note that while some of them are enabled by default on initial
install of "blank" site in the supported platform, they are
not forced as enabled by the running daily maintenance monitor,
so we marked them as [S]oft[E]nabled.

Here is a complete list with corresponding flags for every
module/theme: [S]upported, [B]undled, [F]orce[E]nabled,
[S]oft[E]nabled or [F]orce[D]isabled. [NA] means that
this module is used without the need to enable it.

Supported core version is listed for every module or theme
as [D6] and/or [D7].

Contrib:

 admin ---------------------- [D6,D7] --- [S] [B] [SE]
 advagg --------------------- [D6] ------ [S]
 ais ------------------------ [D7] ------ [S]
 audio ---------------------- [D5,D6] --- [S]
 backup_migrate ------------- [D6,D7] --- [S] [B]
 blockcache_alter ----------- [D6,D7] --- [S] [B]
 boost ---------------------- [D6,D7] --- [S] [B]
 cache_backport ------------- [D6] ------ [S] [B] [NA]
 ckeditor ------------------- [D6,D7] --- [S]
 config_perms --------------- [D6,D7] --- [S] [B]
 core_library --------------- [D7] ------ [S] [B]
 css_emimage ---------------- [D6,D7] --- [S] [B]
 css_gzip ------------------- [D6] -------------- [FD]
 dbtuner -------------------- [D6] ------ [S] [B]
 devel ---------------------- [D6,D7] ----------- [FD]
 esi ------------------------ [D6] ------ [S] [B]
 expire --------------------- [D6,D7] --- [S] [B] [FE]
 fbconnect ------------------ [D6,D7] --- [S]
 fckeditor ------------------ [D6] ------ [S]
 filefield_nginx_progress --- [D6,D7] --- [S] [B] [FE]
 flood_control -------------- [D7] ------ [S] [B]
 fpa ------------------------ [D6,D7] --- [S] [B]
 httprl --------------------- [D6,D7] --- [S] [B]
 imagecache ----------------- [D6,D7] --- [S]
 imagecache_external -------- [D6,D7] --- [S]
 javascript_aggregator ------ [D6] -------------- [FD]
 l10n_update ---------------- [D6,D7] ----------- [FD]
 login_security ------------- [D6] ------ [S] [B]
 nocurrent_pass ------------- [D7] ------ [S] [B]
 performance ---------------- [D6,D7] ----------- [FD]
 poormanscron --------------- [D6] -------------- [FD]
 private_upload ------------- [D6] ------ [S] [B]
 purge ---------------------- [D6,D7] --- [S] [B] [FE]
 readonlymode --------------- [D6,D7] --- [S] [B]
 redis ---------------------- [D6,D7] --- [S] [B] [NA]
 responsive_images ---------- [D7] ------ [S]
 robotstxt ------------------ [D6,D7] --- [S] [B] [FE]
 rubik ---------------------- [D6,D7] --- [S] [B] [SE]
 seckit --------------------- [D6,D7] --- [S] [B]
 securesite ----------------- [D6] ------ [S] [B]
 site_verify ---------------- [D6,D7] --- [S] [B]
 supercron ------------------ [D6] -------------- [FD]
 taxonomy_edge -------------- [D6,D7] --- [S] [B]
 textile -------------------- [D6,D7] --- [S] [B]
 tinybrowser ---------------- [D6,D7] --- [S]
 tinymce -------------------- [D6] ------ [S]
 variable_clean ------------- [D6,D7] --- [S] [B]
 vars ----------------------- [D7] ------ [S] [B]
 views_content_cache -------- [D6,D7] --- [S] [B]
 views404 ------------------- [D6] ------ [S] [B]
 wysiwyg_spellcheck --------- [D6,D7] --- [S]

Core:

 cookie_cache_bypass -------- [D6] -------------- [FD]
 dblog ---------------------- [D6,D7] ----------- [FD]
 path_alias_cache ----------- [D6] -------------- [FE]
 syslog --------------------- [D6,D7] ----------- [FD]

Provision [E]xtensions [M]aster [S]atellite:

 provision_boost ------------ [D6,D7] --- [S] [B] [EM,ES]
 provision_cdn -------------- [D6,D7] --- [S] [B] [EM,ES]
 provision_civicrm ---------- [D6,D7] --- [S] [B] [ES]
 registry_rebuild ----------- [D6,D7] --- [S] [B] [EM,ES]

Hostmaster [E]xtensions [S]atellite:

 aegir_custom_settings ------ [D6] ------ [S] [B] [FE] [ES]
 css_emimage ---------------- [D6] ------ [S] [B] [FE] [ES]
 ctools --------------------- [D6] ------ [S] [B] [FE] [ES]
 features ------------------- [D6] ------ [S] [B] [FE] [ES]
 features_extra ------------- [D6] ------ [S] [B] [FE] [ES]
 hosting_advanced_cron ------ [D6] ------ [S] [B] [FE] [ES]
 hosting_backup_gc ---------- [D6] ------ [S] [B]      [ES]
 hosting_backup_queue ------- [D6] ------ [S] [B]      [ES]
 hosting_cdn ---------------- [D6] ------ [S] [B]      [ES]
 hosting_platform_pathauto -- [D6] ------ [S] [B] [FE] [ES]
 hosting_task_gc ------------ [D6] ------ [S] [B] [FE] [ES]
 protect_critical_users ----- [D6] ------ [S] [B] [FE] [ES]
 revision_deletion ---------- [D6] ------ [S] [B] [FE] [ES]
 strongarm ------------------ [D6] ------ [S] [B] [FE] [ES]
 userprotect ---------------- [D6] ------ [S] [B] [FE] [ES]


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

    /var/aegir/config/includes/barracuda_log.txt
    /data/disk/user/log/octopus_log.txt
    /var/aegir/install.log (remove the password)
    /root/.barracuda.cnf
    /root/.USER.octopus.cnf

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

