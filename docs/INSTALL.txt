
### IMPORTANT!

* After initial installation please reboot your system and then run
  the `barracuda up-stable` upgrade to complete all tasks and prepare
  the system for production use -- it is very important especially on
  newer systems like Debian Jessie.

* BOA requires minimal, supported OS, with no services installed.
  The only acceptable exceptions are: sshd and mail servers.

* Don't run any installer via sudo.
  You must be logged in as root or `sudo -i` first.

* Don't run any system updates before running Barracuda installer.
  You should use vanilla system.

* Please never use HEAD version on any production server. Always use Stable.
  The HEAD can be occasionally broken and should be used **only** for testing!


### Installing BOA system on a public server/VPS

1. Configure your domain DNS to point its wildcard enabled A record to your
   server IP address, and make sure it propagated on the Internet by trying
   `host server.mydomain.org` or `getent hosts server.mydomain.org` command
   on any other server/system.

   See our DNS wildcard configuration example for reference: http://bit.ly/UM2nRb

   NOTE! You shouldn't use anything like "mydomain.org" as your hostname.
         It should be some **subdomain**, like "server.mydomain.org".

   You **don't** need to configure your hostname (on the server) before
   running BOA installer, since BOA will do that for you, automatically.

2. Please read docs/NOTES.txt for other related details.

3. Download and run BOA Meta Installer.

   $ cd;wget -q -U iCab http://files.aegir.cc/BOA.sh.txt;bash BOA.sh.txt

4. Install Barracuda and Octopus.

   You must specify the kind of install with {in-stable|in-head} or for
   legacy versions with {in-2.4|in-2.3|in-2.2}, location with {local|public},
   your hostname and email address, as shown further below.

   Specifying Octopus username is optional. It will use "o1" if empty.

   The one before last part {ask|mini|max|none} is optional, if you wish
   to control Octopus platforms install mode, as explained below.
   Note that "none" is a special option you can use to not install any
   built-in platform, while "ask" is a default mode if you don't specify
   this option at all.

   The last {newrelickey|php-7.0|php-5.6|php-5.5|php-all|nodns} part is
   optional and can be used either to install New Relic Apps Monitor (you should
   replace the "newrelickey" keyword with a valid license key), or to define
   single PHP version to install and use both for Master and Satellite instances.
   When "php-all" is defined, then all available versions will be installed,
   but 5.5 will be used by default. You can later install or modify PHP version
   used via _PHP_MULTI_INSTALL, _PHP_CLI_VERSION and _PHP_FPM_VERSION, but
   the _PHP_SINGLE_INSTALL variable must be set empty to not override other
   related variables. The "nodns" option allows to skip DNS and SMTP checks.

   # Stable on public server - prompt for every platform install
   $ boa in-stable public server.mydomain.org my@email o1

   # Stable on public server - no prompt with 3xD6 + 3xD7 only
   $ boa in-stable public server.mydomain.org my@email o1 mini

   # Stable on public server - no prompt with all platforms and New Relic
   $ boa in-stable public server.mydomain.org my@email o1 max newrelickey

   To install HEAD instead of Stable, use the same commands, but
   replace "in-stable" with "in-head"

   To install Legacy version instead of Stable, use the same commands, but
   replace "in-stable" with "in-2.4", "in-2.3" or "in-2.2".

   Note that once you will install current Stable or HEAD, you can't
   downgrade back to Legacy version!


### Installing BOA system on localhost

1. Please read docs/NOTES.txt

2. Download and run BOA Meta Installer.

   $ cd;wget -q -U iCab http://files.aegir.cc/BOA.sh.txt;bash BOA.sh.txt

3. Install Barracuda and Octopus.

   You must specify the kind of install with {in-stable|in-head},
   location with {local|public}, and your email address,
   as shown below. For local installs you don't need to specify
   hostname and Octopus username, as it is fully automated.

   The last {ask|mini|max|none} part is optional, if you wish to control
   Octopus platforms install mode, as explained below.

   You can also specify PHP version to install, as shown in examples below.
   The {php-7.0|php-5.6|php-5.5|php-all} argument can be either added
   after {ask|mini|max|none} or specified instead of {ask|mini|max|none}

   # Stable on localhost - prompt for every platform install
   $ boa in-stable local my@email

   # Stable on localhost - prompt for every platform + install all PHP versions
   $ boa in-stable local my@email php-all

   # Stable on localhost - no prompt with 3xD6 + 3xD7 only + single PHP version
   $ boa in-stable local my@email mini php-5.6

   # Stable on localhost - no prompt with all platforms installed
   $ boa in-stable local my@email max

   To install HEAD instead of Stable, use the same commands, but
   replace "in-stable" with "in-head"

   To install Legacy version instead of Stable, use the same commands, but
   replace "in-stable" with "in-2.4", "in-2.3" or "in-2.2".

   The oldest Legacy version (in-2.2) is the last Edition in the 2.2.x series
   which still supported Drupal 5 and used Drush 4 along with old Aegir version.
   Note that once you have current stable or head installed, you can't
   go back to any legacy version.


### Installing more Octopus instances

It is now possible to add stable, head or legacy 2.4 Octopus instances w/o
forcing Barracuda upgrade, plus optionally with no platforms added by default:

   $ boa {in-octopus} {email} {o2} {mini|max|none} {stable|head|2.4}

If {stable|head|2.4} is not specified, it will use current stable.

