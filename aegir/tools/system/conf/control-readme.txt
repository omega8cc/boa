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
### check, which in turn will result with even more e-mails notices sent
### to the site admin e-mail, if these notices are enabled.
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
### Support for Compass Tools via RVM and Bundler with local user gems
###
### ~/static/control/compass.info
###
### This allows to easily install Ruby Version Manager (RVM) by the instance
### owner w/o system admin (root) help. All you need to do is to create empty
### ~/static/control/compass.info file.
###
### The system will check for this file existence every five minutes and will
### Install latest RVM stable with Ruby, so you can easily add and manage
### custom gems and bundles, with exact versions required by various themes
### which depend on Compass Tools.
###
### Note that initial RVM install may take 15 minutes or longer, so remember
### to wait until it is complete and then re-login. Once the initial install
### is complete, you will be able to run 'rvm --version' command, but if it is
### still not available, you just need to wait a bit longer. It may take even
### longer if you have extra SSH sub-accounts, because the system needs to
### install separate RVM along with some problematic gems in every sub-account,
### so the effective wait time will be multiplied.
###
### You can then install and update gems using standard rvm commands. Examples:
###
### rvm all do gem install compass
### rvm all do gem install --conservative toolkit
### rvm all do gem install --conservative --version 3.0.3 compass_radix
###
### Note that this single control file will enable RVM also in all extra
### SSH accounts on your instance, if used. If you will delete this file,
### the system will remove RVM with all gems from all SSH accounts on your
### Aegir Satellite Instance.
###

###
### Support for PHP FPM/CLI version safe switch per Octopus instance
###
### ~/static/control/fpm.info
### ~/static/control/cli.info
###
### This allows to easily switch PHP version by the instance owner w/o system
### admin (root) help. All you need to do is to create ~/static/control/fpm.info
### and ~/static/control/cli.info file with a single line telling the system
### which available PHP version should be used (if installed): 5.5 or 5.6 or
### 5.4 or 5.3
###
### Only one of them can be set, but you can use separate versions for web
### access (fpm.info) and the Aegir backend (cli.info). The system will switch
### versions defined via these control files in 5 minutes or less. We use
### external control files and not any option in the Aegir interface to make
### sure you will never lock yourself by switching to version which may cause
### unexpected problems.
###
### Note that the same version will be used in all platforms and all sites
### hosted on the same Octopus instance. Why not to try latest and greatest
### PHP 5.5 now?
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
### CME ----------- Commerce v.2
### CS7 ----------- Commons 7
### DCE ----------- Commerce v.1
### DCS ----------- Commons 6
### ERP ----------- ERPAL
### GDR ----------- Guardr
### OA7 ----------- OpenAtrium D7
### OAD ----------- OpenAid
### CH2 ----------- OpenChurch 2
### OOH ----------- OpenOutreach
### OPC ----------- OpenPublic
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
