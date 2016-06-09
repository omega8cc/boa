###
### Barracuda
###
### Configuration stored in the /root/.barracuda.cnf file.
### This example is for public install mode - see docs/INSTALL.txt
###
### NOTE: the group of settings displayed below will *not* be overridden
### on upgrade by the Barracuda script nor by this configuration file.
### They can be defined only on initial Barracuda install.
###
_EASY_HOSTNAME="f-q-d-n" #------ Hostname auto-configured via _EASY_SETUP
_LOCAL_NETWORK_HN="" #---------- Hostname if in localhost mode - auto-conf
_LOCAL_NETWORK_IP="" #---------- Web server IP if in localhost mode - auto-conf
_MY_FRONT="master.f-q-d-n" #---- URL of the Aegir Master Instance control panel
_MY_HOSTN="f-q-d-n" #----------- Allows to define server hostname
_MY_OWNIP="123.45.67.89" #------ Allows to specify web server IP if not default
_SMTP_RELAY_HOST="" #----------- Allows to configure simple SMTP relay (w/o pwd)
_SMTP_RELAY_TEST=YES #---------- Allows to skip SMTP availability tests when NO
_THIS_DB_HOST=localhost #------- Allows to use hostname in DB grants when FQDN
###
### NOTE: the group of settings displayed below
### will *override* all listed settings in the Barracuda script,
### both on initial install and upgrade.
###
_AUTOPILOT=NO #----------------- Allows to skip all Yes/No questions when YES
_DEBUG_MODE=NO #---------------- Allows to enable Drush debugging when YES
_MY_EMAIL="my@email" #---------- System admin email
_XTRAS_LIST="" #---------------- See docs/NOTES.txt for details on add-ons
###
_MODULES_FIX=YES #-------------- Allows to skip weekly modules en/dis when NO
_MODULES_SKIP="" #-------------- Modules (machine names) to never auto-disable
_PERMISSIONS_FIX=YES #---------- Allows to skip daily permissions fix when NO
###
_CPU_CRIT_RATIO=9 #------------- Max load per CPU core before killing PHP/Drush
_CPU_MAX_RATIO=6 #-------------- Max load per CPU core before disabling Nginx
_CPU_SPIDER_RATIO=3 #----------- Max load per CPU core before blocking spiders
###
_DB_BINARY_LOG=NO #------------- Allows to enable binary logging when YES
_DB_ENGINE=InnoDB #------------- Allows to specify default engine for Drupal 6
_DB_SERIES=5.5 #---------------- Allows to install new MariaDB version when 10.0
_DB_SERVER=MariaDB #------------ Allows to install only MariaDB DB server
_INNODB_LOG_FILE_SIZE=AUTO #---- Allows to change InnoDB log file size: 10-500
###
_DNS_SETUP_TEST=YES #----------- Allows to skip DNS testing when NO
_EXTRA_PACKAGES="" #------------ Installs listed extra packages with apt-get
_FORCE_GIT_MIRROR="" #---------- Allows to use different mirror (deprecated)
_LOCAL_DEBIAN_MIRROR= #--------- Allows to force non-default Debian mirror
_LOCAL_UBUNTU_MIRROR= #--------- Allows to force non-default Ubuntu mirror
_NEWRELIC_KEY= #---------------- Installs New Relic when license key is set
_SCOUT_KEY= #------------------- Installs Scout App when license key is set
###
_MAGICK_FROM_SOURCES=NO #------- Builds ImageMagick from sources when YES
###
_NGINX_DOS_LIMIT=300 #---------- Allows to override default 250/300 limit
_NGINX_EXTRA_CONF="" #---------- Allows to add custom options to Nginx build
_NGINX_FORWARD_SECRECY=YES #---- Installs PFS Nginx support when YES (default)
_NGINX_LDAP=NO #---------------- Installs LDAP Nginx support when YES
_NGINX_NAXSI=NO #--------------- Installs NAXSI WAF when YES - experimental
_NGINX_SPDY=YES #--------------- Installs SPDY Nginx support when YES (default)
_NGINX_WORKERS=AUTO #----------- Allows to override AUTO with a valid integer
###
_PHP_CLI_VERSION=5.6 #---------- PHP-CLI for Master Instance: 7.0 5.{6,5,4,3}
_PHP_EXTRA_CONF="" #------------ Allows to add custom options to PHP build
_PHP_FPM_DENY="" #-------------- Modify disable_functions -- see info below
_PHP_FPM_VERSION=5.6 #---------- PHP-FPM for Master Instance: 7.0 5.{6,5,4,3}
_PHP_FPM_WORKERS=AUTO #--------- Allows to override AUTO with a valid integer
_PHP_IONCUBE=NO #--------------- Installs ionCube for all PHP versions when YES
_PHP_GEOS=NO #------------------ Installs GEOS for all PHP versions when YES
_PHP_MONGODB=NO #--------------- Installs MONGODB for PHP 5.3-only when YES
_PHP_MULTI_INSTALL="5.6" #------ PHP versions to install: 7.0 5.6 5.5 5.4 5.3
_PHP_SINGLE_INSTALL="" #-------- Allows to force single PHP version, like: 5.6
###
_REDIS_LISTEN_MODE=SOCKET #----- Redis listen mode: SOCKET (recommended) or PORT
_RESERVED_RAM=0 #--------------- Allows to reserve RAM (in MB) for non-BOA apps
_SPEED_VALID_MAX=3600 #--------- Defines Speed Booster hourly cache TTL in sec
_SSH_ARMOUR=NO #---------------- Allows to enhance OpenSSH security when YES
_SSH_FROM_SOURCES=YES #--------- Allows to build OpenSSH from sources on Debian
_SSH_PORT=22 #------------------ Allows to configure non-standard SSH port
_STRICT_BIN_PERMISSIONS=YES #--- Aggressively protect all binaries when YES
_STRONG_PASSWORDS=NO #---------- Configurable length: 8-128, YES (32), NO (8)
###
_CUSTOM_CONFIG_CSF=NO #--------- Protects custom CSF config when YES
_CUSTOM_CONFIG_LSHELL=NO #------ Protects custom Limited Shell config when YES
_CUSTOM_CONFIG_REDIS=NO #------- Protects custom Redis config when YES
_CUSTOM_CONFIG_SQL=NO #--------- Protects custom SQL config when YES
###
_AEGIR_UPGRADE_ONLY=NO #-------- Run only Aegir upgrade when YES (deprecated)
_SYSTEM_UPGRADE_ONLY=NO #------- Managed on the fly with 'system' keyword
###
### Barracuda
###

###
### HINT: Check also control files docs in: docs/ctrl/system.ctrl
###

###
### Extra, special purpose settings are listed below.
###

###
### By default BOA configures your system to use as much RAM as safely available
### but if you want to make the configuration more precize, add this extra
### variable to use MySQLTuner on the fly to detect optimal memory allocation.
### This check is no longer enabled by default, because it is very expensive
### method on systems with not enough resources and many sites hosted.
###
_USE_MYSQLTUNER=NO #------------ Use MySQLTuner to configure SQL limits when YES

###
### You can configure BOA to run automated upgrades to latest stable version
### for both Barracuda and all Octopus instances with three variables, empty
### by default. All three variables must be defined to enable auto-upgrade.
### You can set _AUTO_UP_MONTH and _AUTO_UP_DAY to any date in the past
### if you wish to enable only weekly system upgrades.
###
### Remember that one-time upgrades will include complete upgrade to latest BOA
### stable for Barracuda and all Octopus instances, while weekly upgrade is
### designed to run only 'barracuda up-stable system' upgrade.
###
_AUTO_UP_WEEKLY= #-------------- Day of week (1-7) for weekly system upgrades
_AUTO_UP_MONTH= #--------------- Month (1-12) to define date of one-time upgrade
_AUTO_UP_DAY= #----------------- Day (1-31) to define date of one-time upgrade

###
### You can whitelist extra binaries to make them available for web server
### requests, in addition to already whitelisted, known as safe binaries.
###
### Please be aware that you could easily open security holes by whitelisting
### commands which may provide access to otherwise not available parts of
### the system, because the exec() in PHP doesn't respect other limitations
### like open_basedir directive.
###
### You should list only filenames, not full paths, for example:
###
###   _BACKEND_ITEMS_LIST="git foo bar"
###
_BACKEND_ITEMS_LIST=

###
### The BOA Skynet auto-updates were initially limited to checking for new BOA
### release and notifying the system admin daily, until the system has been
### upgraded to latest stable release.
###
### Next, since people tend to forget about running meta-installers update
### before running barracuda or octopus upgrade, and it generated a ton of
### unneeded tickets, confusion and frustration, we have automated these
### updates, so all your meta-installers were updated daily.
###
### Then #drupageddon happened, and we realized that we could make all existing
### BOA systems secure, auto-magically, in the first 60 minutes after the
### #drupageddon alert was published. Only if we could have a running mechanism
### in place to apply very trivial but how important patch to all your D7 sites/
### /codebases while you were on vacation, out of town, or just AFK anywhere.
###
### So we have added Drupal core monitoring and auto-patching to make sure you
### never run vulnerable codebase again. To make it effective, we have scheduled
### to run these checks hourly.
###
### Then we have added also hourly updates for a few key scripts responsible
### for your system security, self-monitoring and self-healing.
###
### Gradually it grew into its current incarnation, so at the moment BOA Skynet
### auto-updates do these things for you, while you sleep:
###
### * Daily version/release check and notification
### * Hourly update for all meta-installers and related tools
### * Hourly check for D7 core vulnerability and patching if detected
### * Hourly update for key BOA tools, monitors and self-healing agents
### * Hourly check if your DNS resolver works as expected and repair if not
###
### While it is a very convenient to have all this work done for you, and we
### believe that it should be still enabled by default, we should make it
### possible to opt-out from all those auto-updates, if you prefer that your
### BOA system never calls home, and whatever happens, is totally under
### your control.
###
### Now you can disable this convenient magic completely by adding the line:
###
###   _SKYNET_MODE=OFF
###
_SKYNET_MODE=ON

###
### NOTE: the group of settings displayed below is never stored
### permanently in this config file, since they are intended to be used
### only when required/useful for some reason, and while can be added
### manually before running barracuda up-{stable|head} command,
### they will be either removed automatically to not affect
### normal upgrades, or ignored afterwards.
###

###
### You can force Nginx, PHP and/or DB server
### reinstall, even if there are no updates
### available, when set to YES.
###
_NGX_FORCE_REINSTALL=NO
_PHP_FORCE_REINSTALL=NO
_SQL_FORCE_REINSTALL=NO
_GIT_FORCE_REINSTALL=NO

###
### Use YES to force installing everything
### from sources again, even if there are
### no updates available.
###
_FULL_FORCE_REINSTALL=NO

###
### Use YES to run major system upgrade
### from Debian Wheezy to Debian Jessie.
###
_WHEEZY_TO_JESSIE=NO

###
### Use YES to run major system upgrade
### from Debian Squeeze to Debian Wheezy.
###
_SQUEEZE_TO_WHEEZY=NO

###
### Use YES to run migration from Tomcat 6
### to Jetty 7 with Apache Solr 1.4.1
### See also docs/SOLR.txt
###
_TOMCAT_TO_JETTY=NO
