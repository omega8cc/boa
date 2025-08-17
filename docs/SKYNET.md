# Importance of Keeping SKYNET Enabled in BOA

The `_SKYNET_MODE=ON` setting (enabled by default) is essential for maintaining BOA's auto-healing functionality. It ensures that BOA tools remain operational by performing critical checks on components such as cURL, Python, and Lshell, verifying that they function correctly.

**We always have SKYNET enabled on all production servers**, which should give you confidence in its safety and reliability for production environments.

While SKYNET does not send notifications for all of its actions, it logs activities in `/var/log/boa/` and `/var/xdrago/monitor/log/`. It also sends incident notifications for its system monitoring features, unless you disable this by setting `_INCIDENT_REPORT=NO` in the `/root/.barracuda.cnf` file.

BOA is **designed to self-maintain** and even [**self-upgrade**](https://github.com/omega8cc/boa/tree/5.x-pro/docs/SELFUPGRADE.md), provided that the optional cron entries are configured. It is built with the expectation that you are using a supported system and are not making changes beyond managing the hosted Ægir sites. When used as intended, BOA operates flawlessly.

However, performing actions outside of the standard BOA upgrade processes—such as manually installing packages, altering default settings, or disabling `_SKYNET_MODE` by setting `_SKYNET_MODE=OFF`—means you assume full responsibility for any issues that may arise. Manual interventions can cause BOA to behave unpredictably, leading to problems that are beyond our control.

In summary, if you allow BOA to operate in its intended **zero-touch manner**, it will run smoothly for years. Disabling `_SKYNET_MODE` or making manual changes means proceeding at your own risk, and we may not be able to provide assistance.

### For reference, here is a bit of history:

The BOA Skynet auto-updates were initially limited to checking for new BOA release and notifying the system admin daily, until the system has been upgraded to latest stable release.

Next, since people tend to forget about running meta-installers update before running barracuda or octopus upgrade, and it generated a ton of unneeded tickets, confusion and frustration, we have automated these updates, so all your meta-installers were updated daily.

Then #drupageddon happened, and we realized that we could make all existing BOA systems secure, auto-magically, in the first 60 minutes after the #drupageddon alert was published. Only if we could have a running mechanism in place to apply very trivial but how important patch to all your D7 sites/codebases while you were on vacation, out of town, or just AFK anywhere.

So we have added Drupal core monitoring and auto-patching to make sure you never run vulnerable codebase again. To make it effective, we have scheduled to run these checks hourly.

Then we have added also hourly updates for a few key scripts responsible for your system security, self-monitoring and self-healing.

Gradually it grew into its current incarnation, so at the moment BOA Skynet auto-updates do these things for you, while you sleep:

* Daily version/release check and notification
* Every 6 minutes update for all meta-installers and related tools
* Hourly check for D7 core vulnerability and patching if detected
* Hourly update for key BOA tools, monitors and self-healing agents
* Hourly check if your DNS resolver works as expected and repair if not

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
