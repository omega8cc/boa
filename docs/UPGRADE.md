
# Available BOA Branches and Licenses

BOA is available in three main branches, but only LITE is available without license:

- **LITE**: This branch remains completely free to use without any kind of license, as it was from the beginning (previously named HEAD or STABLE). This branch should be considered as **BOA LTS** with slow updates, focused on both security and bug fixes, but very limited new features.

- **DEV**: This branch requires a paid license for both installation and upgrade and includes the latest features, security and bug fixes, and installed services versions. This branch shouldn't be used in production without extensive testing.

- **PRO**: This branch requires a paid license and is available only as an upgrade from either LITE or DEV (or previous HEAD/STABLE). It has regular monthly or bi-monthly releases, closely following the tested DEV branch.

Once you install BOA LITE and want to upgrade to PRO with a license obtained from [Omega8.cc Licenses](https://omega8.cc/licenses), you will need to replace `up-lite` in all examples below with `up-pro`.

Once you install BOA LITE or PRO and want to upgrade to DEV with a license from [Omega8.cc Licenses](https://omega8.cc/licenses), you will need to replace `up-lite` in all examples below with `up-dev`.

## Important Notes for Standard/Manual BOA Upgrade

If you haven't run a full barracuda+octopus upgrade to the latest BOA edition yet, don't use any partial upgrade modes explained further below. Once the new BOA latest is available, you must run *full* upgrades with the commands:

```sh
screen
wget -qO- http://files.aegir.cc/BOA.sh.txt | bash
barracuda up-lite
barracuda up-lite system              # Recommended on major upgrade
octopus up-lite all force
bash /var/xdrago/manage_ltd_users.sh  # Recommended on major upgrade
bash /var/xdrago/daily.sh             # Recommended on major upgrade
```

For silent, logged mode with an email message sent once the upgrade is complete, but no progress displayed in the terminal window, you can alternatively run:

```sh
screen
wget -qO- http://files.aegir.cc/BOA.sh.txt | bash
barracuda up-lite log
octopus up-lite all force log
```

Note that the silent, non-interactive mode will automatically say Y/Yes to all prompts and is thus useful for running auto-upgrades scheduled in cron.

**Important:** Do not run any installer via `sudo`. You must be logged in as root or use `sudo -i` first.

All commands will honor settings in their respective config files:

- `/root/.barracuda.cnf`
- `/root/.o1.octopus.cnf`

However, arguments specified on the command line will take precedence. See the upgrade modes explained below.

## Available Standard Upgrade Modes

Download and run (as root) BOA Meta Installers first:

```sh
wget -qO- http://files.aegir.cc/BOA.sh.txt | bash
```

To upgrade the system and Aegir Master Instance to the latest version, use:

```sh
screen
barracuda up-lite
```

To upgrade a selected Aegir Satellite Instance to the latest version, use:

```sh
screen
octopus up-lite o1 force
```

To upgrade *all* Aegir Satellite Instances to the latest version, use:

```sh
screen
octopus up-lite all force
```

## Available Custom Upgrade Modes

You can append `log` as the last argument to every command, and it will write the output to the file instead of the console, respectively:

- `/var/backups/reports/up/barracuda/*`
- `/var/backups/reports/up/octopus/*`

Examples:

```sh
screen
barracuda up-lite log
octopus up-lite all force log
```

A detailed backend log on the barracuda upgrade is always stored in `/var/backups/`.

You can append `system` as the last argument to the barracuda command, and it will upgrade only the system without running the Aegir Master Instance upgrade. It will also write the output to the file instead of the console:

- `/var/backups/reports/up/barracuda/*`

Example:

```sh
screen
barracuda up-lite system
```

Note that while both `log` and `system` modes are "silent" (they don't display anything in your console), they will send the log via email to the address specified in the config file: `/root/.barracuda.cnf`.

It is recommended that you start `screen` before running commands using the "silent" mode to avoid confusion or incomplete tasks when your SSH connection drops for any reason.

It is possible to set/force the upgrade mode on the fly using optional arguments: `{aegir|platforms|both}`

Note that `none` is similar to `both`; however, `both` will force aegir plus platforms upgrade, while `none` will also honor settings from the octopus instance cnf file, where currently only `aegir` mode is defined with `_HM_ONLY=YES` option.

Examples:

```sh
screen

octopus up-lite o1 aegir
octopus up-lite o1 platforms log
octopus up-lite all aegir log
octopus up-lite all platforms
```

## NOTE on Aegir Platforms

Since BOA no longer installs all bundled Aegir platforms during Octopus installation and upgrades, you will need to add some keywords to `~/static/control/platforms.info` and run the Octopus upgrade to have these platforms added as explained in the [documentation](https://github.com/omega8cc/boa/tree/5.x-dev/docs) you can find in the file `~/control/README.txt` within your Octopus account.
