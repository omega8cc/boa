# Ægir Upgrade via Octopus On-Demand without Root Access

You can now launch an Ægir upgrade to (re)install platforms listed in the file `~/static/control/platforms.info` (see below) by creating an empty PID file:

```sh
~/static/control/run-upgrade.pid
```

This file, if it exists, will launch your Ægir upgrade in just a few minutes and will be automatically deleted afterward. This means that you can upgrade your Ægir instance easily to install supported platforms even if you don't have root access or are on a hosted BOA system.

Note that this PID file will be ignored if there is no `platforms.info` file, as explained in [PLATFORMS.md](https://github.com/omega8cc/boa/tree/5.x-lts/docs/PLATFORMS.md). It is also ignored while `~/static` or `~/static/control` is a symlink.

# Barracuda and Octopus Upgrade on Schedule with Root Access

You can launch a BOA after-midnight self-upgrade, either for the system only or also for the Ægir instances, by adding supported variables to the file:

```sh
/root/.barracuda.cnf
```

You can configure BOA to run automated upgrades to the latest head version for both Barracuda and all Octopus instances with three variables, which are empty by default. All three variables must be defined to enable auto-upgrade.

You can set `_AUTO_UP_MONTH` and `_AUTO_UP_DAY` to any date in the past or future (e.g., `_AUTO_UP_MONTH=2` with `_AUTO_UP_DAY=29`) if you wish to enable only weekly system upgrades.

Remember that day/month upgrades will include a complete upgrade to the latest BOA head for Barracuda and all Octopus instances, while weekly upgrades are designed to run only the `barracuda up-<tier> system` upgrade, where `<tier>` is the value of `_AUTO_VER` (which defaults to this box's own BOA tree — see below).

You can further modify the auto-upgrade by specifying the upgrade tier — `dev`, `pro`, or `lts` — with the `_AUTO_VER` variable. Additionally, you can control which PHP versions are installed during the upgrade with the `_AUTO_PHP` variable: `php-min` (or its alias `php-all`) installs PHP 8.3, 8.4, and 8.5 with 8.4 as the default, while `php-max` installs all supported PHP versions; any other value is ignored.

Note that the start times are governed by the `_AUTO_UP_*` hour/minute variables below. On an ordinary operator box, if you leave those unset, the defaults place the day/month Barracuda pass (system and Ægir Master upgrade) shortly after midnight (00:15), the weekly system pass five minutes later (00:20), and the Octopus pass (all Octopus-based Ægir instances) about an hour later (01:15). On hosted BOA systems these are forced to a fixed later schedule — approximately 3 AM for the Barracuda passes and 4 AM for the Octopus pass — regardless of the values above.

The weekly system pass always starts five minutes after the time set for the day/month Barracuda pass (on the next weekday when that time is 23:55 or later), and it does not run at all on the day/month date: the full upgrade does everything it would, and a weekly pass run after it would keep the Octopus pass from starting.

> **NOTE:** All three main `_AUTO_UP_*` variables must be defined to enable auto-upgrade.

```ini
_AUTO_UP_WEEKLY=  # Day of week (1-7) for weekly system upgrades
_AUTO_UP_MONTH=   # Month (1-12) to define the date of one-time upgrade
_AUTO_UP_DAY=     # Day (1-31) to define the date of one-time upgrade
_AUTO_VER=        # The BOA tier to use; if unset, defaults to this box's own BOA tree (dev/pro/lts)
_AUTO_PHP=        # Force php-min, php-all, or php-max; otherwise ignored
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

# Forced System Upgrade for a PHP Security Release

Some PHP security releases cannot wait for the weekly window. For those, a BOA release sets a PHP security floor in `BOA.sh.txt` (`_PHP_SEC_FLOOR`): the first fixed point release of each affected minor version, for example `8.4.27`. A release PHP no longer fixes takes BOA's own backported patch, written as `<release>+<id>`, for example `8.1.34+<id>`: a build of that release counts as below the floor until it carries the patch (see SECURITY.md, "Security backports for older PHP releases"). The floor is empty unless such a release is out, and an empty floor does nothing.

The system agent (`BOA.sh.txt`, run by `clear.sh` every 5 minutes) compares each PHP version installed on the box with its floor, by PHP's own version rules. When one is older, it starts `barracuda up-<tree> system noscreen`, the pass that rebuilds PHP to the pinned releases, on the box's own tree as `/var/log/barracuda_log.txt` records it. It starts the pass at the end of its run, after the BOA tools are refreshed, so nothing else of that run overlaps it.

This pass also runs with `_SKYNET_MODE=OFF` and on boxes without any `_AUTO_UP_*` schedule: a known remote code execution hole is worse than the risks of the pass, and a system pass leaves the Ægir Master Instance as it is. The barracuda launcher, which otherwise refuses every run with `_SKYNET_MODE=OFF`, lets this one pass through. With `_SKYNET_MODE=OFF` the agent mails `_MY_EMAIL` once, when it first sees the floor, with the time the pass will start.

A version waits until the pin of the box's tree (its `_PHPNN_VRN` in that tree's `BARRACUDA.sh.txt`, read from files.boa.io as the launcher reads it, or from the box's mirror when that gives nothing) reaches its floor, the tree carries the backported patch where the floor names one, and the pin's source tarball is on the box's mirror. Each box starts at a fixed spread of up to 30 minutes, after the first run that saw the floor and again when such a wait ends. The pass also waits while an install, upgrade, nightly database dump, xoct or xcopy verb, SQL maintenance, mydumper or myloader run, or an xmass or standby seed younger than two days is in flight, and never starts during a major OS upgrade.

When a major OS upgrade is staged in `/root/.barracuda.cnf` (one of barracuda's `_X_TO_Y=YES` hop flags), the pass would run it too, so the agent mails `_MY_EMAIL` once and holds the pass until that upgrade has been run or the flag removed. With `_SKYNET_MODE=OFF` it also waits until the box has a launcher that honours the override.

If a version is still below the floor after a pass, the next one starts 12 hours later. After three passes that changed nothing, the agent mails `_MY_EMAIL` once and starts no more passes for that floor: run `barracuda up-<tree> system` by hand. With `_INCIDENT_REPORT=OFF` no mail is sent.

The state is `/etc/boa/control/php-sec-floor.<sum>.txt` (the time of the next allowed start, the passes started and the versions they were for), removed once every version is at or above its floor. Decisions are logged in `/var/log/boa/php-sec-floor.log`, the pass itself in `/var/log/boa/barracuda-php-floor.log`.
