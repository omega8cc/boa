## Importance of Keeping SKYNET Enabled in BOA

The `_SKYNET_MODE=ON` setting (enabled by default) is essential for maintaining BOA's auto-healing functionality. It ensures that BOA tools remain operational by performing critical checks on components such as cURL, Python, and Lshell, verifying that they function correctly.

**We always have SKYNET enabled on all production servers**, which should give you confidence in its safety and reliability for production environments.

While SKYNET does not send notifications for all of its actions, it logs activities in `/var/xdrago/log/` and `/var/xdrago/monitor/log/`. It also sends incident notifications for its system monitoring features, unless you disable this by setting `_INCIDENT_EMAIL_REPORT=NO` in the `/root/.barracuda.cnf` file.

BOA is **designed to self-maintain** and even [**self-upgrade**](https://github.com/omega8cc/boa/tree/5.x-dev/docs/SELFUPGRADE.md), provided that the optional cron entries are configured. It is built with the expectation that you are using a supported system and are not making changes beyond managing the hosted Ægir sites. When used as intended, BOA operates flawlessly.

However, performing actions outside of the standard BOA upgrade processes—such as manually installing packages, altering default settings, or disabling `_SKYNET_MODE` by setting `_SKYNET_MODE=OFF`—means you assume full responsibility for any issues that may arise. Manual interventions can cause BOA to behave unpredictably, leading to problems that are beyond our control.

In summary, if you allow BOA to operate in its intended **zero-touch manner**, it will run smoothly for years. Disabling `_SKYNET_MODE` or making manual changes means proceeding at your own risk, and we may not be able to provide assistance.
