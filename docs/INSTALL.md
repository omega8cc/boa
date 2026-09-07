# Preparations Before Installing BOA

- Make sure that IPv6 is not activated -- it's not supported yet, so BOA will disable it anyway.
- Add your SSH keys to your VPS root -- BOA will disable password for root over SSH.
- BOA requires minimal, supported OS, with no web/sql services installed.
- Don't run any installer via sudo. You must be logged in as root directly.
- Don't run any system updates or modifications before installing BOA.
- Please read [docs/NOTES.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/NOTES.md) for other related details.

# BOA Installation Procedures Chain

   **Don't reboot your VM until all procedures are finalized, including post-install auto-upgrades.**

   When invoked via `boa` command, it will run installation is several steps, automatically:

   1. The `autoinit` phase to upgrade vendor provided OS to the matching Devuan release (Daedalus from Bookworm and older, Excalibur from Trixie)
   2. The `barracuda install` phase to install BOA system and Ægir Master
   3. The `barracuda upgrade` phase to complete system installation
   4. The `octopus install` phase to install your first Ægir Satellite
   5. The `octopus upgrade` phase to enable Let's Encrypt certificate for your Ægir
   6. The `barracuda upgrade` phase again to install CSF firewall and DNS cache

   **NOTE!** While steps 2-5 will be visible to you in your SSH terminal (unless you will use silent mode explained further below), the last step will happen within 30 minutes launched from cron in the background, so it's important that you don't reboot and don't use the installed Ægir before the last step is complete.

   **But how you will know it's ready?** Once all procedures are finalized you will see **three (3) lines** reported by this command:

   ```sh
   boa info | grep -c Percona
   ```

   **REMEMBER: don't reboot your VM until all procedures are finalized, including post-install auto-upgrades.**

   Now it's safe and recommended to reboot your server to make sure it's running correct installed Linux kernel supplied by Devuan -- either via your vendor control panel or directly via accelerated system reboot:

   ```sh
   boa reboot
   ```

# Installing BOA System on a Public Server/VPS

1. Configure your domain DNS to point its wildcard-enabled A record to your server IP address, and make sure it propagated on the Internet by trying `host server.mydomain.org` or `getent hosts server.mydomain.org` command on any other server/system.

   See our DNS wildcard configuration guidance for reference: [https://docs.boa.io/self-hosting/before-you-install](https://docs.boa.io/self-hosting/before-you-install)

   **NOTE!** You shouldn't use anything like "mydomain.org" as your hostname. It should be some **subdomain**, like "server.mydomain.org".

2. Configure your permanent hostname on the server before running BOA installer, even if BOA will do that for you, automatically. We recommend this step in case the host/vendor VM enforces some placeholder hostname via cloud-init or other tools on reboot.

   ```sh
   hostname -b server.mydomain.org
   echo server.mydomain.org > /etc/hostname
   ```

3. Download and run BOA Meta Installers.

   ```sh
   wget -qO- https://files.boa.io/BOA.sh.txt | bash
   ```

4. Prepare your system by removing `systemd` and upgrading to the matching Devuan release from any compatible Debian version -- Buster, Bullseye, Bookworm, or Trixie. Bookworm and older bases upgrade to Devuan Daedalus, while Trixie upgrades to Devuan Excalibur.

   ```sh
   autoinit
   ```

   **NOTE:** You can omit this step and run `boa` install as explained in step 5. It will record your command, run `autoinit` for you, and then will run your `boa` install command automatically. Once complete, you should receive an email from the system with all output details logged.

   **NOTE:** It's recommended that you simply wait 10 minutes and then log back in to inspect autoinit logs to make sure there is a line at the bottom saying: "The system is now ready for boa install"

   ```sh
   cat /root/.autoinit.log
   ```

   There's also a verbose log of what happened if you are interested:

   ```sh
   cat /root/.autoinit-verbose.log
   ```

   `autoinit` answers the one question that used to stop this step: a `grub-pc` whose boot-device answer is empty (hand-built and some vendor VMs) cannot be configured without a terminal, and every later `apt` run on the box fails on it. The verbose log then shows `grub ==> Seeding the empty grub-pc install device with /dev/sda` and the conversion carries on; any package `dpkg` still leaves unconfigured after a hop is listed in a `WARN: dpkg ==> packages left unconfigured` line. Should packages still be unconfigured once the conversion is otherwise complete, `autoinit` repairs once more and, failing that, stops before the BOA install with an `ERROR` that names them and the two commands to run (`dpkg --configure -a`, `apt-get -f install`); running `autoinit` again then continues where it stopped.

   If the log nevertheless ends with a `grub-pc` warning, fix GRUB by hand before proceeding to the BOA stack install:

   ```sh
   DEBIAN_FRONTEND=dialog dpkg --configure grub-pc
   dpkg --configure -a
   ```

   Use the dialog to select the appropriate device (usually `/dev/sda`) and once it completes successfully, you can proceed with the BOA installation steps.

5. Install Barracuda and Octopus.

   **NOTE:** Always start with a screen session!

   ```sh
   screen
   ```

   To make sure that you are using all available arguments in the correct order please always check the built-in how-to:

   ```sh
   boa help
   ```

   You must specify the version of install with `in-lts` plus kind with `public`, your `hostname` and `email` address, as shown further below.

   Specifying Octopus `username` is optional. It will use `o1` if empty.

   The `email` address becomes the client-level control panel account (named
   `<username>.ftp`, sharing the shell account password). The separate
   admin-level (uid-1) account uses a derived `root@<hostname>` address, so
   its notices land in the local root mailbox on the server; generate its
   one-time login link with `su -s /bin/bash o1 -c "drush @hm uli"`. To give
   the admin account a real address instead, append the optional trailing
   token `admail=admin@example.com` to any install command — it also
   overrides the default admin address on hosted systems, and must differ
   from the client `email`. To change it later, edit `_MY_OCTO_EMAIL` in
   `/root/.<username>.octopus.cnf` (picked up by future notices and, on the
   next upgrade run, by the instance's system mail address); the panel
   admin account's own email is changed in the control panel, and the two
   are allowed to differ by design.

   The last `{percona-8.4|newrelickey|php-8.5|php-min|php-max|nodns}` part is optional and can be used either to install Percona version other than default 5.7 (can be `percona-8.0` or `percona-8.4`) or New Relic Apps Monitor (you should replace the `newrelickey` keyword with a valid license key), or to define a single PHP version to install and use both for Ægir Master and Satellite instances.

   The `nodns` option allows skipping DNS and SMTP checks.

   When `php-min` is defined, then 3 versions will be installed: `8.5`, `8.4`, `8.3`, with `8.4` configured as default.

   When `php-max` is defined, then all supported versions will be installed and `8.4` configured as default.

   You can later install or modify PHP versions active on your system during `barracuda` upgrade with commands like:

   `barracuda php-idle disable` -- disables versions not used by any site on the system

   `barracuda php-idle enable` -- re-enables and re-builds versions previously disabled

   `barracuda up-lts php-8.5` -- forces the system to use only single version (will cause sites brief downtime)

   `barracuda up-lts php-max` -- installs all supported versions if not installed before

   `barracuda up-lts php-min` -- installs PHP 8.5, 8.4, 8.3, and uses 8.4 by default

   `barracuda up-lts percona-8.0` -- runs upgrade to Percona 8.0 (production ready)

   `barracuda up-lts percona-8.4` -- runs upgrade to Percona 8.4 (production ready)

   If you wish to later define your own set of installed PHP versions, you can do so by modifying variables in the `/root/.barracuda.cnf` file, where you can find `_PHP_MULTI_INSTALL`, `_PHP_CLI_VERSION`, and `_PHP_FPM_VERSION` -- note that the `_PHP_SINGLE_INSTALL` variable must be set empty to not override other related variables. However, you also need to add dummy entries for versions not installed and not used yet to any octopus instance `~/static/control/multi-fpm.info` file, because otherwise `barracuda` will ignore versions not used yet and will automatically remove them from `_PHP_MULTI_INSTALL` on upgrade. These dummy entries should look like this:

   ```sh
   place.holder1.dont.remove 7.3
   place.holder2.dont.remove 8.0
   place.holder3.dont.remove 5.6
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

   - Barracuda and Octopus with 3 PHP versions in silent non-interactive mode
     ```sh
     boa in-lts public server.mydomain.org my@email o1 php-min silent
     ```

   - Barracuda and Octopus with all 12 PHP versions
     ```sh
     boa in-lts public server.mydomain.org my@email o1 php-max
     ```

   - Barracuda and Octopus with 1 PHP version
     ```sh
     boa in-lts public server.mydomain.org my@email o1 php-8.5
     ```

   - Barracuda and Octopus with Percona 8.4 and 3 PHP versions
     ```sh
     boa in-lts public server.mydomain.org my@email o1 percona-8.4
     ```

   - Barracuda and Octopus with New Relic and 3 PHP versions
     ```sh
     boa in-lts public server.mydomain.org my@email o1 newrelickey
     ```

   - Barracuda without Octopus with 3 PHP versions in silent non-interactive mode
     ```sh
     boa in-lts public server.mydomain.org my@email system
     ```

   **NOTE:** Since BOA no longer installs all bundled Ægir platforms during initial system installation, you will need to add some keywords to `~/static/control/platforms.info` and run Octopus upgrade to have these platforms added as explained in the docs you can find in the file `~/static/control/README.txt` within your Octopus account or online at [docs/PLATFORMS.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/PLATFORMS.md)

# Post-install auto-upgrade and reboot

   **Don't reboot your VM until all procedures are finalized, including post-install auto-upgrades.**

   When invoked via `boa` command, it will run installation is several steps, automatically.

   **But how you will know it's ready?** Once all procedures are finalized you will see **three (3) lines** reported by this command:

   ```sh
   boa info | grep -c Percona
   ```

   **REMEMBER: don't reboot your VM until all procedures are finalized, including post-install auto-upgrades.**

   Now it's safe and recommended to reboot your server to make sure it's running correct installed Linux kernel supplied by Devuan -- either via your vendor control panel or directly via accelerated system reboot:

   ```sh
   boa reboot
   ```

# Installing More Octopus Instances

You can add more Octopus instances easily:

```sh
boa in-octopus my@email o2 lts
```

Like above but in silent non-interactive mode:

```sh
boa in-octopus my@email o2 lts silent
```

# Installing BOA System on Localhost (for local development)

Local mode installs the same full BOA stack — Nginx, per-site PHP-FPM, Percona,
Ægir/Hostmaster and one Octopus tenant — on the private hostname `aegir.local`, with no
public IP or DNS. It is meant for local development and testing on your own machine.

It must run inside a virtual machine or an LXC/container guest, not directly on bare metal,
on Devuan — or on a compatible Debian release, which the installer first migrates to Devuan
for you via `autoinit`. As with a public install, add your SSH key to `root` before you
start. You do not need to specify a hostname, an Octopus username, or any public DNS.

1. Please read [docs/NOTES.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/NOTES.md).

2. Download and run BOA Meta Installers.

   ```sh
   wget -qO- https://files.boa.io/BOA.sh.txt | bash
   ```

3. Install Barracuda and Octopus.

   You must specify the version of install with `in-lts`, plus kind with `local`, and your `email` address, as shown below. For local installs, you don't need to specify hostname and Octopus username.

   You can also specify the PHP version to install, as shown in the examples below.

   - Barracuda and Octopus
     ```sh
     boa in-lts local my@email
     ```

   - Barracuda and Octopus with 12 PHP versions
     ```sh
     boa in-lts local my@email php-max
     ```

   - Barracuda and Octopus with 3 PHP versions
     ```sh
     boa in-lts local my@email php-min
     ```

   - Barracuda and Octopus with single PHP version
     ```sh
     boa in-lts local my@email php-8.5
     ```

4. Know when it is ready and how to reach it.

   The installation finishes the same way as a public install: the command
   `boa info | grep -c Percona` reports **three (3)** lines. It is then safe to reboot
   with `boa reboot`.

   Your Ægir control panel is available at **https://aegir.local/user**, and your first
   Octopus tenant at **https://o1.sub.aegir.local**. Because `aegir.local` is a private
   hostname, HTTPS uses a self-signed certificate, so your browser shows a security warning —
   this is expected for local development.
