
###
### Super fast site cloning and migration
###
### It is now possible to enable blazing fast migrations and cloning even sites
### with complex and giant databases with this empty control file:
###
### ~/static/control/MyQuick.info
###
### By the way, how fast is the super-fast? It's faster than you would expect!
### We have seen it speeding up the clone and migrate tasks normally taking
### 1-2 hours to... even 3-6 minutes! Yes, that's how fast it's!
###
### This file, if exists, will enable a super fast per table and parallel DB
### dump and import, although without leaving a conventional complete database
### dump file in the site archive normally created by Aegir when you run
### not only the backup task, but also clone, migrate and delete tasks, hence
### also restore task will not work anymore.
###
### We need to emphasise this again: with this control file present all normally
### super slow tasks will become blazing fast, but at the cost of not keeping
### an archived complete database dump file in the archive of the site directory
### where it would be otherwise included.
###
### Of course the system still maintains nightly backups of all your sites
### using the new split sql dump archives, but with this control file present
### you won't be able to use restore task in Aegir, because the site archive
### won't include the database dump -- you can still find that sql dump split
### into per table files in the backups directory, though, in the subdirectory
### with timestamp added, so you can still access it manually, if needed.
###

###
### Let's Encrypt support for live certificates
###
### Your Aegir system by default comes with Let's Encrypt support in demo mode,
### so you won't hit LE limits for real certificates just by playing around.
### This means that unless you have already added the control file, Aegir will
### create a "demo" or "fake" LE certificates. Once you are ready to go live,
### simply add an empty control file and run Verify task on the site with
### enabled Encryption. Once the tasks completes in all-green, you can edit
### the site's node again to make the Encryption Required, if you prefer.
###
### ~/static/control/ssl-live-mode.info
###
### It is a one-time operation, so even if you will delete this control file
### later, the system will not switch your instance back to LE demo mode.
###

###
### Support for PHP-FPM version switch per Octopus instance (also per site)
###
### ~/static/control/fpm.info
###
### This file, if exists and contains supported and installed PHP-FPM version,
### will be used by running every 2-3 minutes system agent to switch PHP-FPM
### version used for serving web requests by this Octopus instance.
###
### IMPORTANT: If used, it will switch PHP-FPM for all Drupal sites
### hosted on the instance, unless multi-fpm.info control file also exists.
###
### Supported values for single PHP-FPM mode which can be written in this file:
###
### 7.4
### 7.3
### 7.2
### 7.1
### 7.0
### 5.6
###
### NOTE: There must be only one line and one value (like: 7.3) in this file.
### Otherwise it will be ignored.
###
### NOTE: if the file doesn't exist, the system will create it and set to the
### lowest available PHP version installed, not to the system default version.
### This is to guarantee backward compatibility for instances installed
### before upgrade to BOA-4.1.3, when the default PHP version was 5.6,
### as otherwise after the upgrade the system would automatically switch such
### accounts to the new default PHP version which is 7.3, and this could break
### most of the sites hosted, never before tested for PHP 7.3 compatibility.
###

###
### It is now possible to make all installed PHP-FPM versions available
### simultaneously for sites on the Octopus instance with additional
### control file:
###
### ~/static/control/multi-fpm.info
###
### This file, if exists, will switch all sites listed in it to their
### respective PHP-FPM versions as shown in the example below, while all
### other sites not listed in multi-fpm.info will continue to use PHP-FPM
### version defined in fpm.info instead, which can be modified independently.
###
### foo.com 7.3
### bar.com 7.2
### old.com 5.6
###
### NOTE: Each line in the multi-fpm.info file must start with main site name,
### followed by single space, and then the PHP-FPM version to use.
###

###
### Support for PHP-CLI version switch per Octopus instance (all sites)
###
### ~/static/control/cli.info
###
### This file, while similar to fpm.info, if exists and contains supported
### and installed PHP version, will be used by running every 2-3 minutes
### system agent to switch PHP-CLI version for this Octopus instance, but
### it will do this for all hosted sites. There is no option to switch this
### or override per site hosted.
###
### Supported values which can be written in this file:
###
### 7.4
### 7.3
### 7.2
### 7.1
### 7.0
### 5.6
###
### There must be only one line and one value (like: 7.2) in this control file.
### Otherwise it will be ignored.
###
### NOTE: if the file doesn't exist, the system will create it and set to the
### lowest available PHP version installed, not to the system default version.
### This is to guarantee backward compatibility for instances installed
### before upgrade to BOA-4.1.3, when the default PHP version was 5.6,
### as otherwise after the upgrade the system would automatically switch such
### accounts to the new default PHP version which is 7.3, and this could break
### most of the sites hosted, never before tested for PHP 7.3 compatibility.
###
### IMPORTANT: this file will affect only Drush on command line and Drush
### in Aegir backend, used for all tasks on hosted sites, but it will not
### affect PHP-CLI version used by Composer on command line, because Composer
### is installed globally and not per Octopus account, so it will use system
### default PHP version, which is, since BOA-4.1.3, PHP 7.3 and can be
### changed only by changing system default _PHP_CLI_VERSION in the file
### /root/.barracuda.cnf and running barracuda upgrade.
###

###
### Support for forced Drush cache clear in the Aegir backend
###
### ~/static/control/clear-drush-cache.info
###
### Octopus instance will pause all scheduled tasks in its queue, if it will
### detect a platform build from the makefile in progress, to make sure
### that no other running task could break the build.
###
### This is great, until there will be a broken build, and Drush will fail
### to clean up all leftovers from its .tmp/cache directory, which in turn
### will pause all tasks in the queue for up to 24-48 hours, until the cache
### directory will be automatically purged by running daily cleanup tasks,
### designed to not touch anything not old enough (24 hours at minimum)
### to not break any running builds.
###
### If you need to unlock the tasks queue by forcefully removing everything
### from the Aegir backend Drush cache, you can create an empty control file:
### ~/static/control/clear-drush-cache.info
###

###
### Support for New Relic monitoring with per Octopus instance license key
###
### ~/static/control/newrelic.info
###
### This new feature will disable global New Relic monitoring by deactivating
### server-level license key, so it can safely auto-enable or auto-disable it
### every 5 minutes, but per Octopus instance -- for all sites hosted on
### the given instance -- when a valid license key is present in the special
### new ~/static/control/newrelic.info control file.
###
### Please note that valid license key is a 40-character hexadecimal string
### that New Relic provides when you sign up for an account.
###
### To disable New Relic monitoring for the Octopus instance, simply delete
### its ~/static/control/newrelic.info control file and wait a few minutes.
###
### Please note that on a self-hosted BOA you still need to add your valid
### license key as _NEWRELIC_KEY in the /root/.barracuda.cnf file and run
### system upgrade with at least 'barracuda up-stable' first. This step is
### not required on Omega8.cc hosted service, where New Relic agent is already
### pre-installed for you.
###

###
### Support for RVM to install Compass Tools or NPM to install Gulp/Bower
###
### ~/static/control/compass.info
###
### Details: https://github.com/omega8cc/boa/blob/master/docs/RVM.txt
###

###
### Customize Octopus platform list via control file
###
### ~/static/control/platforms.info
###
### This file, if exists and contains a list of symbols used to define supported
### platforms, allows to control/override the value of _PLATFORMS_LIST variable
### normally defined in the /root/.${_USER}.octopus.cnf file, which can't be
### modified by the Aegir instance owner with no system root access.
###
### IMPORTANT: If used, it will replace/override the value defined on initial
### instance install and all previous upgrades. It takes effect on every future
### Octopus instance upgrade, which means that you will miss all newly added
### distributions, if they will not be listed also in this control file.
###
### Supported values which can be written in this file, listed in a single line
### or one per line:
###
### Drupal 9 based
###
### LHG ----------- Lightning
### THR ----------- Thunder
### VBE ----------- Varbase
###
### Drupal 8 based
###
### OPG ----------- Opigno LMS
### SOC ----------- Social
###
### Drupal 7 based
###
### D7P D7S D7D --- Drupal 7 prod/stage/dev
### AGV ----------- aGov
### CME ----------- Commerce v.2
### CS7 ----------- Commons
### DCE ----------- Commerce v.1
### GDR ----------- Guardr
### OA7 ----------- OpenAtrium
### OAD ----------- OpenAid
### OLS ----------- OpenLucius
### OOH ----------- OpenOutreach
### OPC ----------- OpenPublic
### OPO ----------- Opigno LMS
### PPY ----------- Panopoly
### RST ----------- Restaurant
### UC7 ----------- Ubercart
###
### Drupal 6 based
###
### D6P D6S D6D --- Pressflow (LTS) prod/stage/dev
### DCS ----------- Commons
### UCT ----------- Ubercart
###
### You can also use special keyword 'ALL' instead of any other symbols to have
### all available platforms installed, including newly added in all future BOA
### system releases.
###
### Examples:
###
### ALL
### LHG VBE D7P D7S D7D
###

###
### Support for optional Drupalgeddon daily checks on all hosted D7 sites
###
### ~/static/control/drupalgeddon.info
###
### Previously enabled by default, now requires this control file to still
### run daily, because it may generate some false positives not always possible
### to avoid or silence, so it no longer makes sense to run this check daily,
### especially after BOA has run it automatically for a month and finally even
### disabled automatically all clearly compromised sites.
###
### Note that your system administrator may still enable this with root level
### control file /root/.force.drupalgeddon.cnf, so it will still run, even
### if you will not create the Octopus instance level empty control file:
### ~/static/control/drupalgeddon.info
###
### Please note that current version of Drupalgeddon Drush extension needs
### the 'update' module to be enabled to avoid even more false positives,
### so BOA will enable the 'update' module temporarily while running this
### check, which in turn will result with even more emails notices sent
### to the site admin email, if these notices are enabled.
###
