
# How-To Run a Major OS Upgrade

Unlike non-major system upgrades, which can be run with **BARRACUDA** using the Self-Upgrade How-To [docs/SELFUPGRADE.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/SELFUPGRADE.md), a major OS upgrade requires different procedures explained below. There are two options: Modern, which is very reliable and easy to use but gives you only two upgrade paths—to Devuan Chimaera or Devuan Daedalus, and Classic, which allows you to upgrade just to the next supported Debian or Devuan OS version.

If you don’t mind several Classic procedures to get to the latest supported Devuan version, or if you wish to continue running your BOA on Debian, then the Classic procedure is for you.

But if you prefer to have all major OS upgrade multi-steps and versions automated to get to the latest supported Devuan version, then the Modern procedure is for you.

## HOW-TO: Launch Modern Major OS Auto-Upgrade

You can easily upgrade your system from any supported Debian version, starting with Debian Jessie, to Devuan Chimaera or Devuan Daedalus, which are both systemd-free equivalents of Debian Bullseye and Debian Bookworm. You can upgrade from Devuan Beowulf or Chimaera to the recommended Devuan Daedalus using the same procedure.

**NOTE:** Only systems running Percona 5.7 are currently supported.

Please follow the required steps closely!

First, update your BOA Meta Installers with:

```sh
wget -qO- http://files.aegir.cc/BOA.sh.txt | bash
```

Start with a quick barracuda system upgrade for a smooth experience later.

```sh
screen
barracuda up-lts system
```

**1. CREATE A FRESH VM BACKUP SNAPSHOT**

**2. TEST the freshly created backup by using it to create a new test VM**

**3. DO NOT CONTINUE UNTIL IT WORKS**

Reboot the server to make sure there are no issues with the boot process.

```sh
boa reboot
```

If the reboot worked and there are no issues, you are ready for the automated magic...

```sh
touch /root/.run-to-chimaera.cnf
  or
touch /root/.run-to-daedalus.cnf

service clean-boa-env start
```

Once started, the system will launch a series of `barracuda up-lts system` and reboots until it migrates any supported Debian or Devuan version to Devuan Chimaera or Devuan Daedalus.

### Caveats for Unreliable Boot Process on Some Hosts Like Linode

Linode (now owned by Akamai) is known for an unreliable system boot process. Unlike many other hosts, it relies on the Lassie watchdog service when you issue a reboot from the system and not from your Linode control panel.

Unfortunately, the Lassie watchdog pretty often fails to mount the filesystem, and the boot halts until you click on the "Reboot" link in your control panel for the particular VPS. Worse yet, using the "Reboot" link doesn't always help either, and you have to use the "Power Off" and then "Power On" links.

Sometimes even those steps don't bring your server back with a successful boot, so unless you are prepared to try your luck with boot process management in the LISH console, your only rescue option will be restoring your VPS from the Linode backup -- which you have enabled and created a fresh backup before attempting the major upgrade.

### Note on Legacy Systems

Servers running Debian Jessie or Debian Stretch must auto-upgrade to Devuan Chimaera first -- they cannot run the auto-upgrade to Devuan Daedalus. Once on Chimaera, they can auto-upgrade to Devuan Daedalus.

## HOW-TO: Launch Classic Major OS Upgrade

You can easily upgrade your BOA system from any supported Debian or Devuan version, starting with Debian Jessie, to any supported newer version.

The key difference between classic and modern automated procedures is that the automated procedure supports upgrades only to Chimaera or Daedalus, while the classic procedure allows you to select the target system flavor and version according to your preference. However, we do not recommend running BOA on Debian anymore, as it is no longer regularly tested.

**NOTE:** Only systems running Percona 5.7 are currently supported.

Please follow the required steps closely!

First, update your BOA Meta Installers with:

```sh
wget -qO- http://files.aegir.cc/BOA.sh.txt | bash
```

The procedure discussed above automates major OS upgrades by running them in the multi-step cycle, but you can still run the major OS upgrade with classic `barracuda up-lts system` command if you prefer, after adding the respective variable to `/root/.barracuda.cnf`.

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

### NOTE on unused PHP versions automatic deactivation

Both the automated major OS upgrade tools and the classic manual major OS upgrade with barracuda will automatically disable all installed but not used in any hosted site PHP versions, effectively enforcing an otherwise optional procedure normally triggered on barracuda upgrade if the control file exists: `/root/.allow-php-multi-install-cleanup.cnf`.

It will not affect migration/upgrade from Debian Bullseye to Devuan Chimaera, though, since it doesn’t involve re-installing all existing PHP versions normally required in other major upgrades, which otherwise significantly extends the procedure for no good reasons (not used PHP versions should be skipped and deactivated).

To re-install disabled PHP versions after all upgrades are completed, run this command:

```sh
barracuda php-idle enable
```

To disable unused PHP versions again, run this command:

```sh
barracuda php-idle disable
```
