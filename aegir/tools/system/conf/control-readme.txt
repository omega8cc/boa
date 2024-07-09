
###
### Aegir upgrade on-demand
###
### You can now launch Aegir upgrade to (re)install platforms listed in the file
### ~/static/control/platforms.info (see further below) by creating empty file:
###
###   ~/static/control/run-upgrade.pid
###
### This file, if exists, will launch your Aegir upgrade in just a few minutes,
### and will be automatically deleted afterwards. This means that you can
### upgrade your Aegir instance easily to install supported platforms
### even if you don't have root access or are on hosted BOA system.
###
### Note that this pid file will be ignored if there will be no platforms.info
### file, as explained further below.
###


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
### Even faster site cloning and migration
###
### It is now possible to speed up the already blazing fast migrations and
### cloning with this empty control file:
###
###  ~/static/control/FastTrack.info
###
### This file, if exists, will drastically reduce the number of tasks otherwise
### launched automatically in preparation for clone and migrate, namely:
###
###  1. Both source and target platforms will no longer be verified
###  2. The site will no longer be verified before running clone or migrate
###
### Please carefully consider implications, though, because there are very good
### reasons for these extra tasks to be launched before running clone or migrate
### to make sure that any issues are detected and fixed for you early and not
### during migration or clone, which could otherwise break the site and leave it
### in some state not easy to fix, especially without root access to the system.
###
### The potential reasons to disable these extra tasks with the help of
### this new control file can be twofold:
###
###  1. To restore default and much faster Aegir own behaviour
###  2. To help those running mass migrations to avoid running duplicate tasks
###
### Still, it's your responsibility to run these extra verify tasks when you
### need to migrate or clone just single site, but you prefer to have them run
### for you automatically as before, you can easily restore previous behaviour:
###
###  1. Create empty ~/static/control/ClassicTrack.info
###  2. Delete ~/static/control/FastTrack.info
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


### Aegir version provided by BOA is now fully compatible with PHP 8.0 and 8.1,
### so both can be used as default versions in the Aegir PHP configuration files
### ~/static/control/cli.info and ~/static/control/fpm.info
###
### !!! >>> PHP CAVEATS for Drupal core 7-10 versions:
###
###   => https://www.drupal.org/docs/7/system-requirements/php-requirements
###   => https://www.drupal.org/docs/system-requirements/php-requirements
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
### 8.3
### 8.2
### 8.1
### 8.0
### 7.4
### 7.3
### 7.2
### 7.1
### 7.0
### 5.6
###
### NOTE: There must be only one line and one value (like: 8.1) in this file.
### Otherwise it will be ignored.
###
### NOTE: if the file doesn't exist, the system will create it and set to the
### lowest available PHP version installed, not to the system default version.
### This is to guarantee backward compatibility for instances installed
### before upgrade to BOA-4.1.3, when the default PHP version was 5.6,
### as otherwise after the upgrade the system would automatically switch such
### accounts to the new default PHP version which is 8.1, and this could break
### most of the sites hosted, never before tested for PHP 8.1 compatibility.
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
### foo.com 8.1
### bar.com 7.4
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
### 8.3
### 8.2
### 8.1
### 8.0
### 7.4
### 7.3
### 7.2
### 7.1
### 7.0
### 5.6
###
### There must be only one line and one value (like: 8.1) in this control file.
### Otherwise it will be ignored.
###
### NOTE: if the file doesn't exist, the system will create it and set to the
### lowest available PHP version installed, not to the system default version.
### This is to guarantee backward compatibility for instances installed
### before upgrade to BOA-4.1.3, when the default PHP version was 5.6,
### as otherwise after the upgrade the system would automatically switch such
### accounts to the new default PHP version which is 8.1, and this could break
### most of the sites hosted, never before tested for PHP 8.1 compatibility.
###
### IMPORTANT: this file will affect only Drush on command line and Drush
### in Aegir backend, used for all tasks on hosted sites, but it will not
### affect PHP-CLI version used by Composer on command line, because Composer
### is installed globally and not per Octopus account, so it will use system
### default PHP version, which is, since BOA-5.0.0, PHP 8.1 and can be
### changed only by changing system default _PHP_CLI_VERSION in the file
### /root/.barracuda.cnf and running barracuda upgrade.
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
###
### Drupal 10.2 based
###
### D102P D102S D102D --- Drupal 10.2 prod/stage/dev
###
###
### Drupal 10.1 based
###
### D101P D101S D101D --- Drupal 10.1 prod/stage/dev
### THR ----------- Thunder
### VBE ----------- Varbase
###
###
### Drupal 10.0 based
###
### D100P D100S D100D --- Drupal 10.0 prod/stage/dev
###
###
### Drupal 9 based
###
### D9P D9S D9D --- Drupal 9 prod/stage/dev
### OLS ----------- OpenLucius
### OPG ----------- Opigno LMS
### SOC ----------- Social
###
###
### Drupal 7 based
###
### D7P D7S D7D --- Drupal 7 prod/stage/dev
### CME ----------- Commerce v.2
### DCE ----------- Commerce v.1
### UC7 ----------- Ubercart
###
###
### Drupal 6 based
###
### D6P D6S D6D --- Pressflow (LTS) prod/stage/dev
### UCT ----------- Ubercart
###
### You can also use special keyword 'ALL' instead of any other symbols to have
### all available platforms installed, including newly added in all future BOA
### system releases.
###
### Examples:
###
### ALL
### D101P D101S SOC
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
### This feature will disable global New Relic monitoring by deactivating
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
### system upgrade with at least 'barracuda up-lts' first. This step is
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
