###
### Octopus
###
### Configuration stored in the /root/.${_USER}.octopus.cnf file.
### This example is for public install mode - see docs/INSTALL.txt
###
### NOTE: the group of settings displayed below
### will *override* all listed here settings in the Octopus script.
###
_USER="o1" #-------------------- Aegir Instance system account name
_MY_EMAIL="my@email" #---------- Aegir Instance owner email
_PLATFORMS_LIST=ALL #----------- Platforms to install - see docs/PLATFORMS.txt
_AUTOPILOT=NO #----------------- Allows to skip all Yes/No questions when YES
_HM_ONLY=NO #------------------- Allows to upgrade Aegir only (deprecated)
_DEBUG_MODE=NO #---------------- Allows to enable Drush debugging when YES
_MY_OWNIP= #-------------------- Allows to specify web server IP if not default
_FORCE_GIT_MIRROR="" #---------- Allows to use different mirror (deprecated)
_THIS_DB_HOST=localhost #------- DB host depends on Barracuda setting (FQDN)
_DNS_SETUP_TEST=YES #----------- Allows to skip DNS testing when NO
_HOT_SAUCE=NO #----------------- Forces new platforms tree on install when YES
_USE_CURRENT=YES #-------------- Forces new platforms tree on upgrade when NO
_DEL_OLD_EMPTY_PLATFORMS="0" #-- Delete empty platforms if verified > X-days-ago
_DEL_OLD_BACKUPS=0 #------------ Delete Aegir/b-migrate backups if > X-days-ago
_DEL_OLD_TMP=0 #---------------- Delete sites temp files if > X-days-ago
_LOCAL_NETWORK_IP= #------------ Web server IP if in localhost mode - auto-conf
_PHP_FPM_VERSION=5.6 #---------- PHP-FPM for Satellite Instance: 7.0 5.{6,5,4,3}
_PHP_CLI_VERSION=5.6 #---------- PHP-CLI for Satellite Instance: 7.0 5.{6,5,4,3}
_PHP_FPM_WORKERS=AUTO #--------- Allows to override AUTO with a valid integer
_PHP_FPM_TIMEOUT=AUTO #--------- Allows to override default 180 when 60-180
_PHP_FPM_DENY="" #-------------- Modify the disable_functions list per instance
_STRONG_PASSWORDS=NO #---------- Configurable length: 8-128, YES (32), NO (8)
_SQL_CONVERT=NO #--------------- DB conversion when innodb (or YES), or myisam
_RESERVED_RAM=0 #--------------- Allows to reserve RAM (in MB) for non-BOA apps
###
### NOTE: the group of settings displayed below will be *overridden*
### by config files stored in the /data/disk/o1/log/ directory,
### but only on upgrade.
###
_DOMAIN="o1.f-q-d-n" #---------- URL of the Aegir control panel
_CLIENT_EMAIL= #---------------- Create client user if different than _MY_EMAIL
_CLIENT_OPTION="SSD" #---------- Currently not used
_CLIENT_SUBSCR="Y" #------------ Currently not used
_CLIENT_CORES="8" #------------- Currently not used
###
### Octopus
###

###
### HINT: Check also control files docs in: docs/ctrl/system.ctrl
###

###
### Extra, special purpose control files are listed below.
###
### NOTE: the group of control files listed below are intended to be used
### by the instance owner to *overwrite* some settings stored in the
### /root/.${_USER}.octopus.cnf file without system admin (root) assistance.
###

###
### /data/disk/${_USER}/static/control/fpm.info
###
### This file, if exists and contains supported and installed PHP-FPM version
### will be used by running every minute /var/xdrago/manage_ltd_users.sh
### maintenance script to switch PHP-FPM version for this Octopus instance,
### if different than defined in the /root/.${_USER}.octopus.cnf file, in the
### _PHP_FPM_VERSION variable. It will also overwrite _PHP_FPM_VERSION value
### there to avoid doing it over and over again every 5 minutes.
###
### IMPORTANT: If used, it will switch PHP-FPM for all Drupal sites
### hosted on the instance, unless multi-fpm.info control file exists.
###
### Supported values for single PHP-FPM mode which can be written in this file:
###
### 7.0
### 5.6
### 5.5
### 5.4
### 5.3
###
### NOTE: There must be only one line and one value in this control file.
### Otherwise it will be ignored.
###
### It is now possible to make all installed PHP-FPM versions available
### simultaneously for sites on the Octopus instance with additional
### control file:
###
### /data/disk/${_USER}/static/control/multi-fpm.info
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
### /data/disk/${_USER}/static/control/cli.info
###
### This file, if exists and contains supported and installed PHP version
### will be used by running every minute /var/xdrago/manage_ltd_users.sh
### maintenance script to switch PHP-CLI version for this Octopus instance,
### if different than defined in the /root/.${_USER}.octopus.cnf file, in the
### _PHP_CLI_VERSION variable. It will also overwrite _PHP_CLI_VERSION value
### there to avoid doing it over and over again every 5 minutes.
###
### NOTE: While current Aegir version 3.x included in BOA works fine with
### latest PHP 7.0, many hosted sites, especially using Drupal 6 core or
### older Drupal 7 core without required patch we have included since 7.43.2,
### will not work properly and Aegir tasks run against those sites may fail,
### so it is recommended to use PHP-CLI 5.6, unless you have verified that all
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
### There must be only one line and one value in this control file.
### Otherwise it will be ignored.
###

###
### /data/disk/${_USER}/static/control/platforms.info
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
