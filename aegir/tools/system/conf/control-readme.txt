
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
### 7.0
### 5.6
### 5.5
### 5.4
### 5.3
###
### NOTE: There must be only one line and one value (like: 7.0) in this file.
### Otherwise it will be ignored.
###
### It is now possible to make all installed PHP-FPM versions available
### simultaneously for sites on the Octopus instance with additional
### control file:
###
### ~/static/control/multi-fpm.info
###
### This file, if exists, will switch all hosted sites to highest
### available PHP-FPM version within the 5.3-5.6 range, with ability
### to override PHP-FPM version per site, if the site's name is listed
### in this additional control file, as shown below:
###
### foo.com 7.0
### bar.com 5.5
### old.com 5.3
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
### NOTE: While current Aegir version 3.x included in BOA works fine with
### latest PHP 7.0, many hosted sites, especially using Pressflow 6 core or
### older Drupal 7 core without required patch we have included since 7.43.2,
### will not work properly and Aegir tasks run against those sites may fail,
### so it's recommended to use PHP-CLI 5.6, unless you have verified that all
### sites on the instance support PHP 7.0 without issues.
###
### Supported values which can be written in this file:
###
### 7.0
### 5.6
### 5.5
### 5.4
### 5.3
###
### There must be only one line and one value (like: 5.6) in this control file.
### Otherwise it will be ignored.
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
### D8R ----------- Drupal 8 (inactive)
### D7P D7S D7D --- Drupal 7 prod/stage/dev
### D6P D6S D6D --- Pressflow 6 p/s/d
### AGV ----------- aGov
### CH2 ----------- OpenChurch 2
### CME ----------- Commerce v.2
### CS7 ----------- Commons 7
### DCE ----------- Commerce v.1
### DCS ----------- Commons 6
### ERP ----------- ERPAL
### GDR ----------- Guardr
### OA7 ----------- OpenAtrium D7
### OAD ----------- OpenAid
### OLS ----------- OpenLucius
### OOH ----------- OpenOutreach
### OPC ----------- OpenPublic
### OPO ----------- Opigno LMS
### OSR ----------- OpenScholar
### PPY ----------- Panopoly
### RER ----------- Recruiter
### RST ----------- Restaurant
### UC7 ----------- Ubercart D7
### UCT ----------- Ubercart D6
###
### You can also use special keyword 'ALL' instead of any other symbols to have
### all available platforms installed, including newly added in all future BOA
### system releases, but excluding Drupal 8 platforms, which can be installed
### only if respective keywords are explicitly listed and Octopus instance PHP
### version is already set to 5.4 or newer - both for CLI and FPM.
###
### Examples:
###
### ALL
### ALL D8R
### D7P D6P OAM MNS OOH RST
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

###
### Support for locking/unlocking web server write access in all codebases
###
### ~/static/control/unlock.info
###
### This new, auto-enabled by default protection will enhance your system
### security, especially for sites in custom platforms you maintain
### in the ~/static directory tree.
###
### It is important to understand that your web server / PHP-FPM runs as your
### shell/ftps user, although with a different group. This allows to maintain
### virtual chroot for Octopus instances, which significantly improves security.
###
### However, it had a serious drawback: the web server had write access in all
### your platforms codebases located in the ~/static directory tree, because
### all files you have uploaded there have the same owner.
###
### While it allows you to use code management which requires web hooks, it also
### opens a door for possible attack vectors, like for the infamous #drupageddon
### disaster, where Drupal allowed attackers to create .php files intended
### to be used as backdoors in future attacks - inside your codebase.
###
### Even if it could affect only custom platforms you maintain in the ~/static
### directory tree, since all built-in Octopus platforms always had Drupal core
### completely write-protected, plus, even if created by attacking bot, these
### extra .php files are completely useless for attackers, because BOA default
### restricted configuration doesn't allow to execute not whitelisted, unknown
### .php files, having codebase writable by your web server is still dangerous,
### because at least theoretically it may open a possibility to overwrite valid
### .php files, so they could be used as an entry point in a future attack.
###
### BOA now protects all your codebases by reverting (daily) ownership on all
### files and directories in your codebase (modules and themes) so they are
### owned by the Aegir backend user and not your shell/ftps user.
###
### While this new default procedure protects all your codebases in the ~/static
### directory tree, and even in the sites/all directory tree, and even in the
### sites/foo.com/modules|themes tree in all your built-in Octopus platforms,
### you can still manage the code and themes with your main and extra shell
### accounts as usual, because your codebase is still group writable, and your
### shell accounts are members of the group not available for the web server.
###
### You can easily disable this default daily procedure with a single switch:
###
### ~/static/control/unlock.info
###
### You can also exclude any custom platform you maintain in the ~/static
### directory tree from this global procedure by adding an empty skip.info
### control file in the given platform root directory, so all other platforms
### are still protected, and only excluded platform is open for write access
### also for the web server. But normally you should never need this unlock!
###
### Please note that this procedure will not affect any platform if you have
### the non-default _PERMISSIONS_FIX=NO setting in your /root/.barracuda.cnf
### file. It will also skip any platform with fix_files_permissions_daily
### variable set to FALSE in the given platform active INI file.
###
