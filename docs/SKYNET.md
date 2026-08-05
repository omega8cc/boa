# Importance of Keeping SKYNET Enabled in BOA

The `_SKYNET_MODE=ON` setting (enabled by default) is essential for maintaining BOA's auto-healing functionality. It ensures that BOA tools remain operational by performing critical checks on components such as cURL, Python, and Lshell, verifying that they function correctly.

**We always have SKYNET enabled on all production servers**, which should give you confidence in its safety and reliability for production environments.

While SKYNET does not send notifications for all of its actions, it logs activities in `/var/log/boa/` and `/var/xdrago/monitor/log/`. It also sends incident notifications for its system monitoring features, unless you disable this by setting `_INCIDENT_REPORT=NO` in the `/root/.barracuda.cnf` file.

BOA is **designed to self-maintain** and even [**self-upgrade**](https://github.com/omega8cc/boa/tree/5.x-dev/docs/SELFUPGRADE.md), provided that the optional cron entries are configured. It is built with the expectation that you are using a supported system and are not making changes beyond managing the hosted Ægir sites. When used as intended, BOA operates flawlessly.

However, performing actions outside of the standard BOA upgrade processes—such as manually installing packages, altering default settings, or disabling `_SKYNET_MODE` by setting `_SKYNET_MODE=OFF`—means you assume full responsibility for any issues that may arise. Manual interventions can cause BOA to behave unpredictably, leading to problems that are beyond our control.

In summary, if you allow BOA to operate in its intended **zero-touch manner**, it will run smoothly for years. Disabling `_SKYNET_MODE` or making manual changes means proceeding at your own risk, and we may not be able to provide assistance.

### For reference, here is a bit of history:

The BOA Skynet auto-updates were initially limited to checking for new BOA release and notifying the system admin daily, until the system has been upgraded to latest stable release.

Next, since people tend to forget about running meta-installers update before running barracuda or octopus upgrade, and it generated a ton of unneeded tickets, confusion and frustration, we have automated these updates, so all your meta-installers were updated daily.

We have also added hourly updates for a few key scripts responsible for your system security, self-monitoring and self-healing.

Gradually it grew into its current incarnation, so at the moment BOA Skynet auto-updates do these things for you, while you sleep:

* Daily version/release check and notification
* Every 6 minutes update for all meta-installers and related tools
* Hourly update for key BOA tools, monitors and self-healing agents
* Hourly check if your DNS resolver works as expected and repair if not
* Automatic OS security-only updates between BOA upgrades, on modern systems

While it is a very convenient to have all this work done for you, and we
believe that it should be still enabled by default, we should make it
possible to opt-out from all those auto-updates, if you prefer that your
BOA system never calls home, and whatever happens, is totally under
your control.

Now you can disable this convenient magic by adding the line:

  `_SKYNET_MODE=OFF`

NOTE: Critically important BOA tools will be still auto-updated every 6 minutes to keep your system ready for upgrade if/when needed and as initially intended.

Better idea, though:

  `_SKYNET_MODE=ON`

### Automatic OS security updates

On modern systems (Devuan Daedalus and Excalibur, Debian Bookworm and Trixie) BOA also keeps the operating system's own **security** updates applied between BOA upgrades, so a freshly disclosed vulnerability does not sit unpatched for days until your next `barracuda` run. This is security-only: general package upgrades remain `barracuda`'s job, and the stack components BOA builds itself (Nginx, PHP, Percona) are excluded. On older systems, whose security archives are dead or dying upstream, it is deliberately skipped.

When a security update includes a new kernel, BOA does not reboot blindly. The kernel is activated through BOA's own graceful reboot flow, with the same gating as before (hosted `*.aegir.cc` systems, or an explicit `/root/.allow.auto.reboot.cnf`), and only inside the silent night maintenance window between 4:00 and 5:00 server time — never at a random hour, and never on a day when a `barracuda` or `octopus` upgrade is scheduled in `/etc/crontab`. Every automatic activation reboot is recorded in `/var/log/boa/kernel-reboot.log` and announced by an email alert to the configured admin address, so an overnight restart is never a mystery.

This is on by default. To opt out and manage OS security updates yourself, add this line to `/root/.barracuda.cnf`:

  `_SYSTEM_AUTO_SECURITY=NO`

Opting out only stops BOA from managing the automatic updates from that point on; it removes nothing already configured.

Because this runs inside `autoupboa`, it is also inactive whenever `_SKYNET_MODE=OFF`: turning Skynet off stands the whole agent down, OS security updates included.
