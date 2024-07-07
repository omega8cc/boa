
# Notes on Available BOA Branches and Licenses

## BOA Branches

BOA is available in three main branches, but only LITE is available for installation:

- **LITE**: Remains completely free to use without any kind of license as it was from the beginning (previously named HEAD or STABLE). This branch should be considered BOA LTS with slow updates, focused on both security and bug fixes, with very limited new feature additions.

- **DEV**: Requires a paid license for both installation and upgrade. It includes the latest features, security updates, bug fixes, and installed service versions. This branch shouldn't be used in production without extensive testing.

- **PRO**: Requires a paid license and is available only as an upgrade from either LITE or DEV (or previous HEAD/STABLE). This branch features regular monthly or bi-monthly releases, closely following the tested DEV branch.

You can install only BOA LITE and optionally upgrade to PRO with a license from [Omega8.cc](https://omega8.cc/licenses).

# IMPORTANT NOTE!

- Since Debian is running systemd, it should be removed before installing BOA, which involves a simple autoinit procedure, as outlined further below.

- BOA requires minimal, supported OS, with no services installed. The only acceptable exceptions are: sshd and mail servers.

- Don't run any installer via sudo. You must be logged in as root directly.

- Don't run any system updates or modifications with apt before running BOA autoinit. You should use the vanilla system provided by your host.

# Installing BOA System on a Public Server/VPS

1. Configure your domain DNS to point its wildcard-enabled A record to your server IP address, and make sure it propagated on the Internet by trying `host server.mydomain.org` or `getent hosts server.mydomain.org` command on any other server/system.

   See our DNS wildcard configuration example for reference: [http://bit.ly/UM2nRb](http://bit.ly/UM2nRb)

   **NOTE!** You shouldn't use anything like "mydomain.org" as your hostname. It should be some **subdomain**, like "server.mydomain.org".

   You **don't** need to configure your hostname (on the server) before running BOA installer, since BOA will do that for you, automatically.

2. Please read [docs/NOTES.md](docs/NOTES.md) for other related details.

3. Download and run BOA Meta Installers.

   ```sh
   wget -qO- http://files.aegir.cc/BOA.sh.txt | bash
   ```

4. Prepare your system by removing systemd and upgrading to Devuan 5 Daedalus from any compatible Debian version -- Buster, Bullseye, or Bookworm.

   ```sh
   autoinit
   ```

   **NOTE:** You can omit this step and run `boa install` as explained in step 5. It will record your command, run autoinit for you, and then will run your boa install command automatically. Once complete, you should receive an email from the system with all output details logged.

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

   You must specify the version of install with `{in-lite|in-dev}` plus kind with `{local|public}`, your hostname and email address, as shown further below.

   Specifying Octopus username is optional. It will use "o1" if empty.

   The last `{newrelickey|php-8.1|php-min|php-max|nodns}` part is optional and can be used either to install New Relic Apps Monitor (you should replace the "newrelickey" keyword with a valid license key), or to define a single PHP version to install and use both for Aegir Master and Satellite instances.

   When "php-min" is defined, then 4 versions will be installed: 8.3, 8.2, 7.4, plus 8.1, configured as default. You can later install or modify PHP versions used via `_PHP_MULTI_INSTALL`, `_PHP_CLI_VERSION`, and `_PHP_FPM_VERSION`, but the `_PHP_SINGLE_INSTALL` variable must be set empty to not override other related variables. The "nodns" option allows skipping DNS and SMTP checks.

   You can enable much more verbose reporting in the console during installation and upgrades for either barracuda or octopus (or both with -boa-) by adding these control files before running installation/upgrade:

   ```sh
   touch /root/.debug-barracuda-installer.cnf
   touch /root/.debug-octopus-installer.cnf
   touch /root/.debug-boa-installer.cnf
   ```

   **NOTE:** You should never use `/root/.debug-barracuda-installer.cnf` unless you need to debug barracuda without running the Aegir Master Instance upgrades because this file will automatically turn off updating system Drush and the Aegir Master Instance on a barracuda upgrade.

   Interestingly, while `/root/.debug-boa-installer.cnf` enables debugging mode for both barracuda and octopus, it will not prevent Aegir Master Instance and Drush updates.

   ### Examples:

   - Barracuda and Octopus with 3 PHP versions in silent non-interactive mode
     ```sh
     boa in-lite public server.mydomain.org my@email o1 php-min silent
     ```

   - Barracuda and Octopus with all 10 PHP versions
     ```sh
     boa in-lite public server.mydomain.org my@email o1 php-max
     ```

   - Barracuda and Octopus with 1 PHP version
     ```sh
     boa in-lite public server.mydomain.org my@email o1 php-8.3
     ```

   - Barracuda and Octopus with New Relic and 3 PHP versions
     ```sh
     boa in-lite public server.mydomain.org my@email o1 newrelickey
     ```

   - Barracuda without Octopus with 3 PHP versions in silent non-interactive mode
     ```sh
     boa in-lite public server.mydomain.org my@email system
     ```

   **NOTE:** Since BOA no longer installs all bundled Aegir platforms during initial system installation, you will need to add some keywords to `~/static/control/platforms.info` and run Octopus upgrade to have these platforms added as explained in the docs you can find in the file `~/control/README.txt` within your Octopus account.

# Installing More Octopus Instances

You can add more Octopus instances easily:

```sh
boa in-octopus my@email o2 lite
```

Like above but in silent non-interactive mode:

```sh
boa in-octopus my@email o2 lite silent
```

# Installing BOA System on Localhost (Old Feature, Needs Work and Testing)

1. Please read [docs/NOTES.md](docs/NOTES.md).

2. Download and run BOA Meta Installers.

   ```sh
   wget -qO- http://files.aegir.cc/BOA.sh.txt | bash
   ```

3. Install Barracuda and Octopus.

   You must specify the kind of install with `{in-lite|in-dev}`, mode with `{local|public}`, and your email address, as shown below. For local installs, you don't need to specify hostname and Octopus username, as it is fully automated.

   You can also specify the PHP version to install, as shown in examples below.

   - Barracuda and Octopus
     ```sh
     boa in-lite local my@email
     ```

   - Barracuda and Octopus with 10 PHP versions
     ```sh
     boa in-lite local my@email php-max
     ```

   - Barracuda and Octopus with 3 PHP versions
     ```sh
     boa in-lite local my@email php-min
     ```

   - Barracuda and Octopus with single PHP version
     ```sh
     boa in-lite local my@email php-8.1
     ```
