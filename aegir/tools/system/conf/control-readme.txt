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
### not equired on Omega8.cc hosted service, where New Relic agent is already
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
### which available PHP version should be used (if installed): 5.5 or 5.4 or 5.3
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
### D7P D7S D7D --- Drupal 7 prod/stage/dev
### D6P D6S D6D --- Pressflow 6 p/s/d
### AGV ----------- aGov
### CME ----------- Commerce v.2
### CS7 ----------- Commons 7
### DCE ----------- Commerce v.1
### DCS ----------- Commons 6
### ERP ----------- ERPAL
### FSR ----------- Feature Server
### GDR ----------- Guardr
### MNS ----------- Managing News
### OA7 ----------- Open Atrium D7
### OAM ----------- Open Atrium D6
### OAY ----------- Open Academy
### OBG ----------- OpenBlog
### OCH ----------- OpenChurch 1
### CH2 ----------- OpenChurch 2
### ODS ----------- Open Deals
### OOH ----------- Open Outreach
### OPC ----------- OpenPublic
### OSR ----------- OpenScholar
### PPY ----------- Panopoly
### RER ----------- Recruiter
### RST ----------- Restaurant
### SRK ----------- Spark
### TTM ----------- Totem
### UC7 ----------- Ubercart D7
### UCT ----------- Ubercart D6
###
### You can also use special keyword 'ALL' instead of any other symbols to have
### all available platforms installed, including newly added in all future BOA
### system releases.
###
### Examples:
###
### ALL
### D7P D6P OAM MNS OOH RST
###
