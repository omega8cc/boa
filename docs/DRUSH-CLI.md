# Drush and PHP-CLI Version Management in BOA

BOA (Barracuda Octopus Ægir) provides robust tools for managing PHP-CLI and Drush versions, giving you control over how Drupal sites are maintained and updated. This document explains the process for **instant PHP-CLI switching** using **configuration files**, and how PHP-CLI interacts with Drush for site management.

---

## Required: Use the `oN.ftp` Limited Shell for All CLI Operations

**Everything described in this document — `vdrush`, PHP-CLI version switching, Composer, and
all other drush operations — works exclusively under the `oN.ftp` limited shell account.**

BOA provisions two separate user accounts per Octopus instance:

- `oN` — the main Unix user, accessible via SSH with a regular bash shell
- `oN.ftp` — the FTP/limited shell user, accessible via SSH with BOA's special shell wrapper

The PHP-CLI version management and `vdrush` described in this document depend on BOA's
**special shell wrapper**, which is only active in the `oN.ftp` limited shell environment.
This wrapper correctly reads and applies the PHP-CLI version you have configured via the
control files described below, and makes `vdrush` available.

Note that PHP-CLI and PHP-FPM are **two independent systems** in BOA. PHP-FPM version is
controlled separately via `~/static/control/fpm.info` or `~/static/control/multi-fpm.info`
(see [PHP-FPM.md](PHP-FPM.md)). The shell wrapper does not automatically match PHP-CLI to
each site's PHP-FPM version — you are responsible for configuring PHP-CLI to match your
sites' PHP-FPM version using the control files, so that drush and Composer run against the
correct PHP version.

**When logged in as `oN` under bash, the shell wrapper is not active.** The PHP-CLI control
files are ignored entirely, `vdrush` will not behave correctly, and you will be running
drush and Composer against whatever PHP version happens to be the system default. Errors
caused by this are difficult to diagnose and are easily mistaken for server or Drupal
problems.

**Always connect as `oN.ftp` when running any drush or Composer command.** The `oN` bash
account should not be used for these operations.

---

## PHP-CLI Version Management in BOA

BOA provides two mechanisms for managing the PHP-CLI version used in command-line operations (such as Drush and Composer):

1. **`~/static/control/cli.info`**: This is the **main configuration file** that defines the
   **default PHP-CLI version** to use across the Octopus instance. If no instant
   configuration switches are present, this version will be used.
2. **Instant Switch Configuration Files**: These files enable instant PHP-CLI version
   switching for command-line and Ægir backend task operations.

### How Instant PHP-CLI Switching Works

In addition to the `cli.info` file, BOA supports **instant PHP-CLI switching** through **specific configuration files** located in `~/static/control/`. The filenames of these configuration files dictate the PHP version to use, and their content is irrelevant. This enables you to switch the PHP-CLI version for Drush, Composer, and other CLI operations, including Ægir tasks, instantly.

> **Reminder:** Instant PHP-CLI switching only works under the `oN.ftp` limited shell,
> and only applies to CLI operations — it does not affect PHP-FPM. See the prerequisite
> section above.

#### Example Instant Switch Files:

- `~/static/control/php85.info`
- `~/static/control/php84.info`
- `~/static/control/php83.info`
- `~/static/control/php82.info`
- `~/static/control/php81.info`
- `~/static/control/php74.info`

Each file corresponds to a specific PHP version. To switch the PHP-CLI version:

1. **Create a configuration file** corresponding to the desired PHP version. For example, to switch to PHP 8.3, create a file named `php83.info` in `~/static/control/`. The content of this file does not matter and can be empty.
2. The system will automatically detect the **highest available PHP version** based on the filenames of these files. You do not need to remove other files for lower PHP versions.

If none of these instant switch files are present, the system will default to the PHP version listed in `~/static/control/cli.info`.

**Note:** These files will switch the PHP-CLI version used *instantly*, unlike the classic `~/static/control/cli.info` which requires 3 minutes to take effect.

### Supported PHP-CLI Versions:

- 8.5, 8.4, 8.3, 8.2, 8.1, 8.0, 7.4, 7.3, 7.2, 7.1, 7.0, 5.6

**However:** Some older PHP versions may no longer be available on your system, because BOA automatically deactivates versions not used by any hosted site. If you need to restore some older PHP version previously available, please open a support ticket with your BOA host, or, if you have root access, run `barracuda php-idle enable` command. If you want to re-install all supported but disabled PHP versions, please run `barracuda up-lts php-max` command. For more details, run `barracuda help` command.

### Important Notes:

- The instant switch files' **content is irrelevant** — what matters is the **filename**.
  These files can be empty or contain any content.
- The system will automatically select the **highest PHP version** based on the filenames of
  the switch files. No need to remove lower-version files.
- The `cli.info` file serves as the **default** PHP-CLI version when no instant switch files
  are present, and it **must contain a valid PHP version** in its content (e.g., `8.1`).
- This smart feature, similarly to the classic `~/static/control/cli.info`, depends on the
  BOA special shell wrapper, which is only active under the `oN.ftp` limited shell account.
  The wrapper reads these control files to determine which PHP-CLI version to use — without
  it, the control files are ignored and drush runs against the system default PHP version.
  The wrapper is additionally temporarily deactivated during both barracuda and octopus
  upgrades to not interfere with complex procedures which depend on system dash shell. For
  this reason any Drush or Composer command you execute in the limited shell account while
  barracuda or octopus upgrade is running will revert to the version defined in the
  system-wide `/root/.barracuda.cnf` file.

### Example of `cli.info`:
```
8.1
```
This version will be used by default if no instant switch files (e.g., `php83.info`) are detected.

---

## Drush Management in BOA

Drush is the primary tool for managing Drupal sites within BOA, allowing you to perform tasks such as installing sites, cloning sites, or migrating them between Platforms, perform database updates, cache clearing etc. Drush integrates seamlessly with BOA’s PHP-CLI management, ensuring that the correct PHP version is always used.

### Key Highlights:

1. Ægir no longer removes local Drush from any platform.
2. Site-local Drush can be invoked using `vdrush`.
3. PHP-CLI version switching for Drush and Composer is instantaneous using the **instant switch configuration files**.
4. Using standalone Drush versions newer than version 8 is deprecated.
5. Drush 8 remains available as `drush8` or simply `drush`.
6. Drush 10 is available as standalone `drush10`.
7. Drush 11 is available as standalone `drush11`.
8. Drush 12 or newer is available only as **site-local**, invoked via `vdrush`.
9. It is important to review specific **caveats** for managing Drush versions further below.

---

### Site-Local Drush is Preserved and Fully Supported

In BOA, Ægir no longer removes the local copy of Drush from platforms during the 'Platform Verify' task. Instead, it locks permissions on the `vendor/drush` directory if present.

This change allows you to easily unlock the local Drush using a new task available on the platform node in the Ægir control panel named 'Unlock Local Drush'. This task is now a required step before you use local `vdrush` or run any updates with `composer` on the command line.

#### Steps to Use Site-Local Drush:

> **Important:** All steps below must be performed as `oN.ftp` under the BOA limited shell,
> not as `oN` under bash. Connecting as `oN` will result in the wrong PHP environment and
> `vdrush` will not work correctly. If `vdrush` has not worked for you in the past, this is
> the most likely reason.

1. Run the 'Unlock Local Drush' task on the site's Platform in Ægir.
2. Connect to your server as `oN.ftp` (not `oN`) using SSH.
3. Find the correct Drush `@site-alias` with the `drush11 aliases` command.
4. Switch to the Platform app root where `vendor` exists using `cd`.
5. Run `vdrush --version` or install it with `composer require drush/drush`.
6. Use `vdrush @site-alias updbst`, `vdrush @site-alias updb`, etc.
7. Run the 'Platform Verify' task to restore compatibility with Drush 8.

---

### Supported Drush Versions:

- **Drush 8**: Available as `drush8` or simply `drush`. It remains the global default version for most operations, compatible with legacy Drupal versions.
- **Drush 10**: Available as `drush10`.
- **Drush 11**: Available as `drush11`.
- **Drush 12**: Available only as **site-local**, invoked with `vdrush`.
- **Drush 13**: Available only as **site-local**, invoked with `vdrush`.

---

## PHP-CLI and Drush Integration

Since Drush relies on the active PHP-CLI version, any changes made to the PHP-CLI version will directly affect Drush operations. The PHP-CLI version can be set either by the **instant switch configuration files** or by the **default `cli.info` file**.

### Example:

- To make Drush use PHP 8.3, create a configuration file named `php83.info` in the `~/static/control/` directory. The system will automatically detect the highest available PHP version, and all Drush operations will use that version instantly.
- If no instant switch files are detected, Drush will default to the PHP version specified in `~/static/control/cli.info`.

---

## Caveats

- When using standalone `drush8`, `drush10`, or `drush11`, please use Drush Aliases — we don’t test anything running standalone Drush commands in the site directory anymore — it’s probably an old habit which should be avoided for standalone Drush — also because it may and will clash with local Drush if also present.
- Note that the Drush Alias name for the site with `drush10` is different than for `drush8` — all dots in the site name should be replaced with hyphens and only the last dot before the domain's last extension should be a dot. Example: `drush8 @sub.domain.top.org` becomes `drush10 @sub-domain-top.org`.
- On every Ægir / Octopus upgrade, all platforms are automatically verified and thus local Drush is by default locked again in all existing platforms.

### Stop Using Standalone System Drush 10 and 11

Why is using standalone system Drush other than Drush 8 deprecated, even if still possible?

All post-8 Drush versions up to 11 could theoretically be used as standalone (on command line but not with Ægir) if their numerous dependencies matched the managed Drupal site codebase.

However, most of the time you will find that some dependencies shared by Drupal and Drush 10+ will clash if you try to use Drush in the standalone, system mode, because Composer can’t track their compatibility when you use Drush not included in the Drupal platform's own codebase.

This makes using standalone system versions of Drush 10+ a very frustrating experience and sometimes even impossible.

Please add local Drush to your Drupal codebase with Composer and use it instead of system-wide `drush10` and `drush11` to avoid headaches.

BOA still provides standalone `drush10` and `drush11`, though, because we still need them to convert Drush 8-type site aliases into Drush 10+ type site aliases, but otherwise these standalone Drush versions are of little use.

By the way, due to constant dependencies versions updates, you could get pretty different versions of the same Drush 10+ release installed depending on *when* you have installed it. Sometimes they will be too old and sometimes too new for the Drupal codebase in question. This makes using them as standalone a completely unpredictable mess.

That’s also why Drush 12 has been officially announced as the first version which can’t be used as standalone at all — no matter how hard you would try.

