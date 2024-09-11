## Ægir Upgrade via Octopus On-Demand without Root Access

You can now launch an Ægir upgrade to (re)install platforms listed in the file `~/static/control/platforms.info` (see below) by creating an empty PID file:

```sh
~/static/control/run-upgrade.pid
```

This file, if it exists, will launch your Ægir upgrade in just a few minutes and will be automatically deleted afterward. This means that you can upgrade your Ægir instance easily to install supported platforms even if you don't have root access or are on a hosted BOA system.

Note that this PID file will be ignored if there is no `platforms.info` file, as explained in [PLATFORMS.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/PLATFORMS.md).

## Barracuda and Octopus Upgrade on Schedule with Root Access

You can launch a BOA after-midnight self-upgrade, either for the system only or also for the Ægir instances, by adding supported variables to the file:

```sh
/root/.barracuda.cnf
```

You can configure BOA to run automated upgrades to the latest head version for both Barracuda and all Octopus instances with three variables, which are empty by default. All three variables must be defined to enable auto-upgrade.

You can set `_AUTO_UP_MONTH` and `_AUTO_UP_DAY` to any date in the past or future (e.g., `_AUTO_UP_MONTH=2` with `_AUTO_UP_DAY=29`) if you wish to enable only weekly system upgrades.

Remember that day/month upgrades will include a complete upgrade to the latest BOA head for Barracuda and all Octopus instances, while weekly upgrades are designed to run only the `barracuda up-lts system` upgrade.

You can further modify the auto-upgrade by specifying either `head` or `dev` with the `_AUTO_VER` variable. Additionally, you can include all supported PHP versions with the `_AUTO_PHP` variable set to "php-min"; otherwise, it will be ignored.

Note that weekly system upgrades will start shortly after midnight on the specified weekday, while the day/month upgrades for both Barracuda and all Octopus instances will start at approximately 3 AM for the system and Ægir Master instance, and at approximately 4 AM for all Octopus-based Ægir instances.

> **NOTE:** All three main `_AUTO_UP_*` variables must be defined to enable auto-upgrade.

```ini
_AUTO_UP_WEEKLY=  # Day of week (1-7) for weekly system upgrades
_AUTO_UP_MONTH=   # Month (1-12) to define the date of one-time upgrade
_AUTO_UP_DAY=     # Day (1-31) to define the date of one-time upgrade
_AUTO_VER=lts     # The BOA version to use (lts by default)
_AUTO_PHP=        # Useful to force php-min, otherwise ignored
```

> **NOTE:** New extra `_AUTO_UP_*` variables can be also defined or default values will be used

```ini
_AUTO_UP_HOUR=    # Hour of the day (0-23) for barracuda upgrades
_AUTO_UP_MINUTE=  # Minute of the hour (0-59) for barracuda upgrades
```

```ini
_AUTO_OCT_UP_HOUR=    # Hour of the day (0-23) for octopus upgrades
_AUTO_OCT_UP_MINUTE=  # Minute of the hour (0-59) for octopus upgrades
```

> **IMPORTANT:** pay attention to use correct values within ranges as listed above. Otherwise you can break and lock your system cron.
