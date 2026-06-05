# Security Audit & Hardened Foundations Edition

## New BOA-5.9.5 PRO/LTS Release Notes

## ⚡ ACTION REQUIRED (self-hosted systems): Linux Kernel Security Update

This release ships with a **new Linux kernel** addressing a kernel-level
security vulnerability. **A reboot is required** to activate it.

There is **no critical Drupal core release** in this cycle.

If you run your own BOA server with root access, we strongly recommend
enabling unattended weekly automation so future kernel and system security
updates are applied — and activated — without manual action.

Add to `/root/.barracuda.cnf`:

```ini
_SKYNET_MODE=ON          # enable weekly self-upgrade automation
_AUTO_UP_WEEKLY=7        # day of week (1-7) for the weekly system upgrade
_AUTO_UP_MONTH=2         # month (1-12) for the one-time full upgrade date
_AUTO_UP_DAY=29          # day (1-31) for the one-time full upgrade date
_AUTO_VER=lts            # BOA version to track (lts by default)
```

> All three `_AUTO_UP_*` variables must be defined to enable auto-upgrade.
> Weekly runs perform only `barracuda up-lts system`; the month/day date
> triggers a full Barracuda + Octopus upgrade. Full reference:
> https://github.com/omega8cc/boa/blob/5.x-lts/docs/SELFUPGRADE.md

Then enable automatic reboot when a new kernel is installed:

```sh
touch /root/.allow.auto.reboot.cnf
```

Together these keep your servers patched and rebooted into the latest kernel
automatically. **Customers on a managed plan at https://omega8.cc/managed have
this handled for them by our team.**

---

## Overview

BOA-5.9.5 PRO/LTS is the product of a full **security audit** across the entire
BOA and Ægir/Provision codebase. In total, **169 commits across six
repositories** went into this release:

| Repository | Branch | Commits |
|---|---|---|
| omega8cc/boa | 5.x-dev | 143 |
| omega8cc/provision | 5.x-dev | 11 |
| omega8cc/drush | 8-boa-micro | 10 |
| omega8cc/hosting_tasks_extra | 5.x-dev | 3 |
| omega8cc/hosting_civicrm | 5.x-dev | 1 |
| omega8cc/hosting_git | 5.x-dev | 1 |

Beyond the audit, the headline changes are the **Devuan Daedalus → Excalibur**
OS upgrade path, a substantial **Valkey/APCu cache-layer overhaul**, and
complete **PHP 8.5 compatibility** in the BOA Drush fork.

---

## Security Audit

This release closes a class of vulnerabilities identified during a systematic
audit of the BOA and Ægir codebase. The work spanned all six repositories.

### Credential exposure

The most impactful finding: SQL passwords were briefly visible in the process
list (`/proc/<pid>/cmdline`) to any non-lshell system user whenever a MySQL/Percona
client was invoked with `-p` on the command line. All such invocations now use
`--defaults-extra-file` or `--defaults-file=/root/.my.cnf`. Legacy `_SQL_PSWD`
reads have been removed throughout, and the `xmass` migration tool no longer
exposes the SQL root password.

In addition, `/proc` is now mounted with **hidepid**, so one Octopus user can
no longer inspect the process list, environment, or command lines of another
Aegir system user or of root-owned processes.

### Shell injection

- Component downloads now default to **HTTPS with certificate validation**,
  closing an HTTP-mirror MITM vector
- The `mysql_cleanup` path uses a strict **SQL-identifier allowlist**
- New helpers — `_is_safe_ident`, `_validate_safe_dir`,
  `_validate_path_prefix`, `_chmod_safe` — enforce safe values before they
  reach the shell
- Across **Provision, hosting_civicrm, hosting_git, and hosting_tasks_extra**,
  the `aegir-shell-injection-audit` fixes close the same class of issues in
  HTTP basic-auth password handling and `drush_shell_exec()` paths

### Privilege escalation & permissions

- Blocked a path where NOPASSWD-sudo `tar` helpers could follow a symlink to
  write into root-owned locations
- `/opt/tmp` scratch root now uses sticky `1777` instead of recursive `777`
- Closed the `daily.sh` `chown -L` symlink-following path
- Tightened default file and directory permissions across the board

### Drush: block evil `*.drush.inc` (with a CiviCRM exception)

A new path-based extension filter (`includes/boa_extension_filter.inc`) blocks
Drush from auto-loading `*.drush.inc` command files located under
tenant-writable paths (`/static/`, `/distro/`, `/platforms/`), removing a
code-execution vector via uploaded files.

**CiviCRM requires a control file — action needed for CiviCRM sites.** CiviCRM
ships its own legitimate Drush command files (`civicrm.drush.inc`,
`cv.drush.inc`, `civicrm_drush.drush.inc`) inside the site tree, which the new
filter would otherwise block. These are needed for **Aegir backend tasks**
(verify, migrate, clone, and similar) to complete on a CiviCRM site, so they
are allowlisted — but only as an explicit, per-Octopus-user opt-in. To enable
the exception for an Octopus user, create the control file:

```sh
touch /data/conf/<octopus-user>_civicrm.txt
```

(The Octopus user is derived from the backend task's `$HOME` under
`/data/disk/`.) When this file is present, the three CiviCRM command-file
basenames are loaded during backend tasks; otherwise they stay blocked.

> **This affects only Aegir backend tasks, not PHP-FPM.** Normal web requests
> to a CiviCRM site never go through Drush, so they are entirely unaffected —
> the site keeps serving traffic exactly as before, with or without the
> control file. The control file is required **only** so that the site's
> *Aegir backend tasks* can load CiviCRM's own Drush commands. If you host
> CiviCRM sites, add the control file for each affected Octopus user before
> running their next verify or migrate task.

### Config-template hardening

PHP (`session.use_strict_mode = 1`, `expose_php = Off`, `local_infile = OFF`),
Nginx, MySQL, SSH, and sysctl templates have all been hardened. The insecure
`wget` shell alias has been removed.

---

## Devuan Daedalus → Excalibur OS Upgrade Path

BOA now better supports upgrading the underlying OS from Devuan Daedalus to Excalibur:

- The upgrade **refuses to proceed if an older Percona version is in use**,
  preventing a broken database after the OS jump
- `/root/.top-daedalus.cnf` is renamed to the Excalibur namespace on upgrade
- **ICU 76.1** becomes the default on supported OS (ICU 76 supports PHP 8.1+
  only; the version check runs for PHP newer than 7.3)
- The obsolete `resolvconf` is removed and `/lib/resolvconf` cleaned up
- A documented NOTE explains the expected **brief PHP downtime** during the
  upgrade

> **Note:** plan the Daedalus → Excalibur upgrade during a maintenance window.
> A short PHP-FPM restart occurs as the PHP builds are relinked against the
> newer ICU and system libraries.

---

## Cache Layer Overhaul (Valkey / Redis / APCu)

The caching stack received a thorough refactor in this cycle:

- **Valkey 9.1.0**
- Restored **socket mode** for the Valkey/Redis listen-mode rewriter
- Resolved the redis module directory under `o_contrib_eleven` on **Drupal 11**
- Unified cache ini settings under the `redis_` namespace; debug logging gated
- Switched to **volatile-lfu** eviction policy; corrected a databases
  off-by-one error
- Hardened the Valkey probe, corrected anonymous-user detection, added
  observability
- Scoped Drupal 7-only redis settings; lowered compression level
- `apc.serializer=igbinary`; `apc.ttl` changed from `0` to `3600`
- New **`_fpm_apcu_reload_sentinel`** elects a single APCu flusher on backend
  recovery, avoiding a thundering-herd of simultaneous flushes

The net effect is more predictable cache behaviour under load and cleaner
recovery after a backend restart.

---

## PHP 8.5 in BOA Drush

The BOA Drush fork (`8-boa-micro`) is now fully PHP 8.5 compatible:

- Implicitly-nullable params made explicitly nullable
- Type hints dropped in favour of compatibility across the PHP 5.6–8.5 range
- Canonical `(int)` cast used instead of the removed `(integer)` cast
- A PHP 8.x backstop masks `E_DEPRECATED` at startup to prevent deprecation
  notices from escalating into fatal aborts
- `drush_shutdown` now reports only fatal-class errors as the
  abnormal-termination cause, reducing false alarms in logs

---

## Provision / Ægir Backend

- **Bootstrap level capped at `CONFIGURATION` for Drupal 8+** in deploy,
  import, install, and verify tasks — except where D8–D11 post-processing
  genuinely needs FULL bootstrap (the over-aggressive F2 cap was reverted)
- **Percona 8.4 compatibility** for `revoke()`, `generate_dump()`, and PDO
  connect; `PDO::MYSQL_ATTR_GET_SERVER_PUBLIC_KEY` guarded with `defined()`;
  `REVOKE`/`DROP` skipped silently when the user does not exist
- `$block_search_root_referer` now **requires a facet param**, fixing a false
  positive on legitimate homepage search (follow-up to the 5.9.3
  search-amplification protection)

---

## New Tools & Features

| Item | Description |
|---|---|
| `xmass` | New full-server migration tool (all instances and sites in one run) |
| `xoct` | The former `xboa` per-account tool, renamed; `xboa` removed |
| `_fpm_apcu_reload_sentinel` | Coordinated single-flusher APCu reload on recovery |
| High-RAM / Very high-RAM tiers | New memory-tuning tiers for large bare-metal hosts |
| `_check_sql_running` | Guard that verifies the DB is up before config updates |
| jetty9 init template | Dedicated sysvinit template for the Solr/Jetty service |

---

## Component Versions

| Component | Version |
|---|---|
| Composer | 2.10.1 |
| Drush | 8.5.2 classic |
| ICU | 76.1 |
| ionCube | 15.5.0 (up to PHP 8.5) |
| Nginx | 1.31.1 |
| PHP | 8.5.7 / 8.4.22 / 8.3.31 / 8.2.31 |
| Pure-FTPd | 1.0.54 |
| screenfetch | 3.9.9 |
| Unbound | 1.25.1 |
| Valkey | 9.1.0 |
| zlib | 1.3.2 |

---

## Important Fixes

- **SSH TCP forwarding regression** that broke Sequel remote SQL access has
  been fixed — local TCP forwarding restored so tunneled database access works
  again
- **New Relic reinstall bug** fixed — `_newrelic_key_check` now detects an
  unchanged signing key and only re-installs when the APT key actually rotates
- Fixed an exit typo in the `nginx.sh` monitor check
- Corrected stale PID-file cleanup logic and dropped the `-rf` flag on `rm`
- Fixed syntax in the `xmass` migration tool

---

## Upgrade Instructions

Run inside a `screen` session as root:

```sh
screen
wget -qO- https://files.boa.io/BOA.sh.txt | bash
barracuda up-lts
octopus up-lts all force
reboot
```

**Do not skip the reboot** — this release includes a new kernel that closes a
kernel-level security vulnerability, and the running kernel is only replaced on
reboot.

For silent logged mode (output to `/var/backups/reports/up/`, emailed on
completion — useful for cron):

```sh
screen
wget -qO- https://files.boa.io/BOA.sh.txt | bash
barracuda up-lts log
octopus up-lts all force log
```

Full upgrade documentation: https://github.com/omega8cc/boa/blob/5.x-dev/docs/UPGRADE.md
Self-upgrade automation: https://github.com/omega8cc/boa/blob/5.x-dev/docs/SELFUPGRADE.md

> **Daedalus → Excalibur note:** if your server is still on Devuan Daedalus,
> the OS upgrade will be offered as part of this cycle. Ensure Percona is on a
> current version first (the upgrade will refuse to proceed otherwise) and
> expect a brief PHP-FPM restart during the transition.

---

## Links

- Commit history (BOA): https://github.com/omega8cc/boa/commits/5.x-dev/
- Commit history (Provision): https://github.com/omega8cc/provision/commits/5.x-dev/
- Full changelog: https://github.com/omega8cc/boa/blob/5.x-dev/CHANGELOG.txt
- License: https://github.com/omega8cc/boa/blob/5.x-dev/DUALLICENSE.md
