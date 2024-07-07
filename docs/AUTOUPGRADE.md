
# Notes on Available BOA Branches and Licenses

BOA is available in three main branches, but only LITE is available for installation:

- **LITE**: This branch remains completely free to use without any kind of license, as it was from the beginning (previously named HEAD or STABLE). This branch should be considered as BOA LTS with slow updates, focused on both security and bug fixes, but very limited new features additions.

- **DEV**: This branch requires a paid license for both installation and upgrade and includes the latest features, security and bug fixes, and installed services versions. This branch shouldn't be used in production without extensive testing.

- **PRO**: This branch requires a paid license and is available only as an upgrade from either LITE or DEV (or previous HEAD/STABLE). It includes regular monthly or bi-monthly releases, closely following the tested DEV branch.

Once you install BOA LITE and want to upgrade to PRO with a license obtained from [Omega8.cc licenses](https://omega8.cc/licenses), you will need to replace `up-lite` in all examples below with `up-pro`.

Once you install BOA LITE or PRO and want to upgrade to DEV with a license from [Omega8.cc licenses](https://omega8.cc/licenses), you will need to replace `up-lite` in all examples below with `up-dev`.

# Automatic BOA System Major Upgrade Tool

You can easily upgrade your system from any supported Debian version, starting with Debian Jessie, to Devuan Chimaera or Devuan Daedalus, which are both systemd-free equivalents of Debian Bullseye and Debian Bookworm.

The same tool can be used to upgrade from Devuan Beowulf to the currently recommended Devuan Daedalus.

**NOTE:** Only systems running Percona 5.7 are supported.

Please follow the required steps closely!

First, update your BOA Meta Installers with:

```sh
$ wget -qO- http://files.aegir.cc/BOA.sh.txt | bash
```

## HOW-TO: Launch Auto-Upgrade Properly

Start with a manual barracuda upgrade.

```sh
$ barracuda up-lite system
```

**1. CREATE A FRESH VM BACKUP SNAPSHOT!**

**2. TEST the freshly created backup by using it to create a new test VM!**

**3. DO NOT CONTINUE UNTIL IT WORKS!**

Reboot the server to make sure there are no issues with the boot process.

```sh
$ reboot
```

If the reboot worked and there are no issues, you are ready for the automated magic...

```sh
$ touch /root/.run-to-chimaera.cnf
  or
$ touch /root/.run-to-daedalus.cnf

$ service clean-boa-env start
```

Once enabled, the system will launch a series of `barracuda up-lite` and reboots until it migrates any supported Debian or Devuan version to Devuan Chimaera or Devuan Daedalus.

**WARNING!**

Expect it to crash completely, so only full restore from the latest backup snapshot of the entire vm will bring it back to life.
do not proceed until you are ready for disaster recovery from a tested backup!

### Caveats for Unreliable Boot Process on some Hosts like Linode

Linode (now owned by Akamai) is known for an unreliable system boot process. Unlike many other hosts, it relies on the Lassie watchdog service when you issue a reboot from the system and not from your Linode control panel.

Unfortunately, the Lassie watchdog pretty often fails to mount the filesystem, and the boot halts until you click on the "Reboot" link in your control panel for the particular VPS.

Worse yet, using the "Reboot" link doesn't always help either, and you have to use the "Power Off" and then "Power On" links.

Sometimes even those steps don't bring your server back with a successful boot, so unless you are prepared to try your luck with boot process management in the LISH console, your only rescue option will be restoring your VPS from the Linode backup -- which you have enabled and created a fresh backup before attempting the major upgrade.

### Note for Legacy Systems

Servers running Debian Jessie or Debian Stretch must auto-upgrade to Devuan Chimaera first -- they cannot run the auto-upgrade to Devuan Daedalus. Once on Chimaera, they can auto-upgrade to Devuan Daedalus.

This tool automates OS upgrades you can still run manually if you prefer, by adding the respective variable to `/root/.barracuda.cnf` and running the standard command `barracuda up-lite system` for the manual steps based upgrade.

### Devuan to Devuan Major OS Upgrades

- Devuan Chimaera => upgrade to Daedalus with `_CHIMAERA_TO_DAEDALUS=YES`
- Devuan Beowulf => upgrade to Chimaera with `_BEOWULF_TO_CHIMAERA=YES`

### Debian to Devuan Major OS Upgrades

- Debian 12 Bookworm => upgrade to Daedalus with `_BOOKWORM_TO_DAEDALUS=YES`
- Debian 11 Bullseye => upgrade to Chimaera with `_BULLSEYE_TO_CHIMAERA=YES`
- Debian 10 Buster => upgrade to Beowulf with `_BUSTER_TO_BEOWULF=YES`
- Debian 9 Stretch => upgrade to Beowulf with `_STRETCH_TO_BEOWULF=YES`
- Debian 8 Jessie => upgrade to Beowulf with `_JESSIE_TO_BEOWULF=YES`

### Debian to Debian Major OS Upgrades

- Debian 11 Bullseye => upgrade to Bookworm with `_BULLSEYE_TO_BOOKWORM=YES`
- Debian 10 Buster => upgrade to Bullseye with `_BUSTER_TO_BULLSEYE=YES`
- Debian 9 Stretch => upgrade to Buster with `_STRETCH_TO_BUSTER=YES`
- Debian 8 Jessie => upgrade to Stretch with `_JESSIE_TO_STRETCH=YES`

**NOTE:** This tool will automatically disable all installed but not used PHP versions in any existing site, effectively enforcing an otherwise optional procedure normally triggered on barracuda upgrade if the control file exists: `/root/.allow-php-multi-install-cleanup.cnf`.

Side note: it will not affect migration/upgrade from Debian Bullseye to Devuan Chimaera, though, since it doesn't involve re-installing all existing PHP versions normally required in other major upgrades, which otherwise significantly extends the procedure for no good reasons (not used PHP versions should be skipped and deactivated).

To re-install disabled PHP versions after all upgrades are completed, run this command:

```sh
$ barracuda php-idle enable
```

To disable unused PHP versions again, run this command:

```sh
$ barracuda php-idle disable
```
