# Preparations Before Installing BOA

- Add your SSH keys to your VPS root-- BOA will disable password for root over SSH.
- BOA requires minimal, supported OS, with no web/sql services installed.
- Don't run any installer via sudo. You must be logged in as root directly.
- Don't run any system updates or modifications before installing BOA.

# Installing BOA System on a Public Server/VPS

1. Configure your domain DNS to point its wildcard-enabled A record to your server IP address, and make sure it propagated on the Internet by trying `host server.mydomain.org` or `getent hosts server.mydomain.org` command on any other server/system.

   See our DNS wildcard configuration example for reference: [http://bit.ly/UM2nRb](http://bit.ly/UM2nRb)

   **NOTE!** You shouldn't use anything like "mydomain.org" as your hostname. It should be some **subdomain**, like "server.mydomain.org".

   You **don't** need to configure your hostname (on the server) before running BOA installer, since BOA will do that for you, automatically.

2. Please read [docs/NOTES.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/NOTES.md) for other related details.

3. Download and run BOA Meta Installers.

   ```sh
   wget -qO- http://files.aegir.cc/BOA.sh.txt | bash
   ```

4. Prepare your system by removing `systemd` and upgrading to Devuan 5 Daedalus from any compatible Debian version -- Buster, Bullseye, or Bookworm.

   ```sh
   autoinit
   ```

   **NOTE:** You can omit this step and run `boa` install as explained in step 5. It will record your command, run `autoinit` for you, and then will run your `boa` install command automatically. Once complete, you should receive an email from the system with all output details logged.

   **NOTE:** It's recommended that you simply wait 10 minutes and then log back in to inspect autoinit logs to make sure there is a line at the bottom saying: "Time for reboot and then you can run boa install"

   ```sh
   cat /root/.autoinit.log
   ```

   There's also a verbose log of what happened if you are interested:

   ```sh
   cat /root/.autoinit-verbose.log
   ```

5. Install Barracuda and Octopus.

   **NOTE:** Always start with a screen session!

   ```sh
   screen
   ```

   You must specify the version of install with `in-lts` plus kind with `public`, your `hostname` and `email` address, as shown further below.

   Specifying Octopus `username` is optional. It will use `o1` if empty.

   The last `{newrelickey|php-8.2|php-min|php-max|nodns}` part is optional and can be used either to install New Relic Apps Monitor (you should replace the `newrelickey` keyword with a valid license key), or to define a single PHP version to install and use both for Ægir Master and Satellite instances.

   The `nodns` option allows skipping DNS and SMTP checks.

   When `php-min` is defined, then only 4 versions will be installed: `8.3`, `8.2`, `7.4`, plus `8.1`, configured as default.

   When `php-max` is defined, then all supported versions will be installed and `8.1` configured as default.

   You can later install or modify PHP versions active on your system during `barracuda` upgrade with commands like:

   `barracuda php-idle disable` -- disables versions not used by any site on the system

   `barracuda php-idle enable` -- re-enables and re-builds versions previously disabled

   `barracuda up-lts php-8.2` -- forces the system to use only single version (will cause sites brief downtime)

   `barracuda up-lts php-max` -- installs all supported versions if not installed before

   `barracuda up-lts php-min` -- installs PHP 8.1, 8.2, 8.3, 7.4, and uses 8.1 by default

   If you wish to later define your own set of installed PHP versions, you can do so by modifying variables in the `/root/.barracuda.cnf` file, where you can find `_PHP_MULTI_INSTALL`, `_PHP_CLI_VERSION`, and `_PHP_FPM_VERSION` -- note that the `_PHP_SINGLE_INSTALL` variable must be set empty to not override other related variables. However, you also need to add dummy entries for versions not installed and not used yet to any octopus instance `~/static/control/multi-fpm.info` file, because otherwise `barracuda` will ignore versions not used yet and will automatically remove them from `_PHP_MULTI_INSTALL` on upgrade. These dummy entries should look like this:

   ```sh
   place.holder1.dont.remove 7.3
   place.holder2.dont.remove 8.0
   place.holder3.dont.remove 7.1
   ```

   The same logic protects existing and used versions from being removed even if they are not listed in the `_PHP_MULTI_INSTALL` variable (they will be re-added automatically if needed).

   You can enable much more verbose reporting in the console during installation and upgrades for either barracuda or octopus (or both with -boa-) by adding these control files before running installation/upgrade:

   ```sh
   touch /root/.debug-barracuda-installer.cnf
   touch /root/.debug-octopus-installer.cnf
   touch /root/.debug-boa-installer.cnf
   ```

   **NOTE:** You should never use `/root/.debug-barracuda-installer.cnf` unless you need to debug barracuda without running the Ægir Master Instance upgrades because this file will automatically turn off updating system Drush and the Ægir Master Instance on a barracuda upgrade.

   Interestingly, while `/root/.debug-boa-installer.cnf` enables debugging mode for both barracuda and octopus, it will not prevent Ægir Master Instance and Drush updates.

   ### Examples:

   - Barracuda and Octopus with 4 PHP versions in silent non-interactive mode
     ```sh
     boa in-lts public server.mydomain.org my@email o1 php-min silent
     ```

   - Barracuda and Octopus with all 10 PHP versions
     ```sh
     boa in-lts public server.mydomain.org my@email o1 php-max
     ```

   - Barracuda and Octopus with 1 PHP version
     ```sh
     boa in-lts public server.mydomain.org my@email o1 php-8.3
     ```

   - Barracuda and Octopus with New Relic and 4 PHP versions
     ```sh
     boa in-lts public server.mydomain.org my@email o1 newrelickey
     ```

   - Barracuda without Octopus with 4 PHP versions in silent non-interactive mode
     ```sh
     boa in-lts public server.mydomain.org my@email system
     ```

   **NOTE:** Since BOA no longer installs all bundled Ægir platforms during initial system installation, you will need to add some keywords to `~/static/control/platforms.info` and run Octopus upgrade to have these platforms added as explained in the docs you can find in the file `~/control/README.txt` within your Octopus account or online at [docs/PLATFORMS.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/PLATFORMS.md)

# Installing More Octopus Instances

You can add more Octopus instances easily:

```sh
boa in-octopus my@email o2 lts
```

Like above but in silent non-interactive mode:

```sh
boa in-octopus my@email o2 lts silent
```

# Installing BOA System on Localhost (needs testing)

1. Please read [docs/NOTES.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/NOTES.md).

2. Download and run BOA Meta Installers.

   ```sh
   wget -qO- http://files.aegir.cc/BOA.sh.txt | bash
   ```

3. Install Barracuda and Octopus.

   You must specify the version of install with `in-lts`, plus kind with `local`, and your `email` address, as shown below. For local installs, you don't need to specify hostname and Octopus username.

   You can also specify the PHP version to install, as shown in the examples below.

   - Barracuda and Octopus
     ```sh
     boa in-lts local my@email
     ```

   - Barracuda and Octopus with 10 PHP versions
     ```sh
     boa in-lts local my@email php-max
     ```

   - Barracuda and Octopus with 4 PHP versions
     ```sh
     boa in-lts local my@email php-min
     ```

   - Barracuda and Octopus with single PHP version
     ```sh
     boa in-lts local my@email php-8.2
     ```
