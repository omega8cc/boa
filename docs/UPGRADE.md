# How To: Upgrade Your BOA System

All standard non-major system upgrades can be run with **BARRACUDA** and all Ægir instances can be upgraded with **OCTOPUS**, but we highly recommend to use the fully automated procedure explained in Self-Upgrade How To: [docs/SELFUPGRADE.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/SELFUPGRADE.md)

## Important Notes for Standard/Manual BOA Upgrade

If you haven't run a full barracuda+octopus upgrade to the latest BOA edition yet, don't use any partial upgrade modes explained further below. Once the new BOA latest is available, you must run *full* upgrades with the commands:

```sh
screen
wget -qO- http://files.aegir.cc/BOA.sh.txt | bash
barracuda up-lts
octopus up-lts all force
```

For silent, logged mode with an email message sent once the upgrade is complete, but no progress displayed in the terminal window, you can alternatively run:

```sh
screen
wget -qO- http://files.aegir.cc/BOA.sh.txt | bash
barracuda up-lts log
octopus up-lts all force log
```

Note that the silent, non-interactive mode will automatically say Y/Yes to all prompts and is thus useful for running auto-upgrades scheduled in cron.

**Important:** Do not run any installer via `sudo`. You must be logged in as root or use `sudo -i` first.

All commands will honor settings in their respective config files:

- `/root/.barracuda.cnf`
- `/root/.o1.octopus.cnf`

However, arguments specified on the command line will take precedence. See the upgrade modes explained below.

To make sure that you are using all available arguments in the correct order please always check the built-in how-to:

```sh
barracuda help
```

```sh
octopus help
```

## Available Standard Upgrade Modes

Download and run (as root) BOA Meta Installers first:

```sh
wget -qO- http://files.aegir.cc/BOA.sh.txt | bash
```

To upgrade the system and Ægir Master Instance to the latest version, use:

```sh
screen
barracuda up-lts
```

To upgrade a selected Ægir Satellite Instance to the latest version, use:

```sh
screen
octopus up-lts o1 force
```

To upgrade *all* Ægir Satellite Instances to the latest version, use:

```sh
screen
octopus up-lts all force
```

## Available Custom Upgrade Modes

You can append `log` as the last argument to every command, and it will write the output to the file instead of the console, respectively:

- `/var/backups/reports/up/barracuda/*`
- `/var/backups/reports/up/octopus/*`

Examples:

```sh
screen
barracuda up-lts log
octopus up-lts all force log
```

A detailed backend log on the barracuda upgrade is always stored in `/var/backups/`.

You can append `system` as the last argument to the barracuda command, and it will upgrade only the system without running the Ægir Master Instance upgrade. It will also write the output to the file instead of the console:

- `/var/backups/reports/up/barracuda/*`

Example:

```sh
screen
barracuda up-lts system
```

Note that while both `log` and `system` modes are "silent" (they don't display anything in your console), they will send the log via email to the address specified in the config file: `/root/.barracuda.cnf`.

It is recommended that you start `screen` before running commands using the "silent" mode to avoid confusion or incomplete tasks when your SSH connection drops for any reason.

It is possible to set/force the upgrade mode on the fly using optional arguments: `{aegir|platforms|both}`

Note that `none` is similar to `both`; however, `both` will force aegir plus platforms upgrade, while `none` will also honor settings from the octopus instance cnf file, where currently only `aegir` mode is defined with `_HM_ONLY=YES` option.

Examples:

```sh
screen

octopus up-lts o1 aegir
octopus up-lts o1 platforms log
octopus up-lts all aegir log
octopus up-lts all platforms
```

## NOTE on PHP versions management

You can install or modify PHP versions active on your system during `barracuda` upgrade with commands like:

`barracuda php-idle disable` -- disables versions not used by any site on the system

`barracuda php-idle enable` -- re-enables and re-builds versions previously disabled

`barracuda up-lts php-8.2` -- forces the system to use only single version (will cause sites brief downtime)

`barracuda up-lts php-max` -- installs all supported versions if not installed before

`barracuda up-lts php-min` -- installs PHP 8.1, 8.2, 8.3, 7.4, and uses 8.1 by default

If you wish to define your own set of installed PHP versions, you can do so by modifying variables in the `/root/.barracuda.cnf` file before running the upgrade, where you can find `_PHP_MULTI_INSTALL`, `_PHP_CLI_VERSION`, and `_PHP_FPM_VERSION` -- note that the `_PHP_SINGLE_INSTALL` variable must be set empty to not override other related variables.

However, you will also need to add dummy entries for versions not installed and not used yet to `~/static/control/multi-fpm.info` file (on any Octopus instance), because otherwise `barracuda` will ignore versions not used yet and will automatically remove them from `_PHP_MULTI_INSTALL` on upgrade. These dummy entries should look like this:

```sh
place.holder1.dont.remove 7.3
place.holder2.dont.remove 8.0
place.holder3.dont.remove 7.1
```

The same logic protects existing and used versions from being removed even if they are not listed in the `_PHP_MULTI_INSTALL` variable (they will be re-added automatically if needed).

## NOTE on Ægir Platforms

Since BOA no longer installs all bundled Ægir platforms during Octopus installation and upgrades, you will need to add some keywords to `~/static/control/platforms.info` and run the Octopus upgrade to have these platforms added as explained in the [documentation](https://github.com/omega8cc/boa/tree/5.x-dev/docs) you can find in the file `~/control/README.txt` within your Octopus account.
