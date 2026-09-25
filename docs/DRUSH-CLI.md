# Drush and PHP-CLI Version Management in BOA

BOA (Barracuda Octopus Ægir) provides robust tools for managing PHP-CLI and Drush versions, giving you control over how Drupal sites are maintained and updated. This document explains the process for **instant PHP-CLI switching** using **configuration files**, and how PHP-CLI interacts with Drush for site management.

---

## Required: Use the `oN.ftp` Limited Shell for All CLI Operations

**Everything described in this document — `vdrush`, PHP-CLI version switching, Composer, and
all other drush operations — applies to the commands you type in your limited shell logins:
`oN.ftp`, and a platform developer login (`oN.<client>-dev`) if you have one.** Both read the
account's control files. The Ægir tasks on your account follow the same control files.

BOA provisions two separate user accounts per Octopus instance:

- `oN` — the system user that runs your Ægir tasks; it has no login shell, so nobody logs in
  as it (on a self-hosted box root can switch to it with `su -s /bin/bash - oN`)
- `oN.ftp` — the FTP/limited shell user, accessible via SSH with BOA's special shell wrapper

The PHP-CLI version management and `vdrush` described in this document depend on BOA's
**special shell wrapper**. Of these two accounts only `oN.ftp` is a login, and its limited
shell runs your commands through the wrapper. The wrapper also runs every Ægir task on your account, which is why the
control files steer those tasks too. It reads and applies the PHP-CLI version you have
configured via the control files described below, and makes `vdrush` available.

Note that PHP-CLI and PHP-FPM are **two independent systems** in BOA. PHP-FPM version is
controlled separately via `~/static/control/fpm.info` or `~/static/control/multi-fpm.info`
(see [PHP-FPM.md](PHP-FPM.md)). The shell wrapper does not automatically match PHP-CLI to
each site's PHP-FPM version — you are responsible for configuring PHP-CLI to match your
sites' PHP-FPM version using the control files, so that drush and Composer run against the
correct PHP version.

**In a bash shell as `oN` (root's `su -s /bin/bash - oN`), the commands you type do not go
through the shell wrapper.** The PHP-CLI control files are ignored for them, `vdrush` will
not behave correctly, and you will be running drush and Composer against whatever PHP
version happens to be the system default. Errors caused by this are difficult to diagnose
and are easily mistaken for server or Drupal problems.

**Always connect as `oN.ftp` when running any drush or Composer command.** A bash shell as
`oN` should not be used for these operations.

---

## PHP-CLI Version Management in BOA

BOA provides three mechanisms for managing the PHP-CLI version used in command-line operations (such as Drush and Composer):

1. **`~/static/control/cli.info`**: This is the **main configuration file** that defines the
   **default PHP-CLI version** to use across the Octopus instance. If no instant
   configuration switches are present, this version will be used.
2. **Instant Switch Configuration Files**: These files enable instant PHP-CLI version
   switching for command-line and Ægir backend task operations.
3. **`~/static/control/cli-per-platform.info`**: one line per platform folder, for an
   account whose platforms need different PHP versions (old and new Drupal cores side by
   side). A listed platform runs on its own version, whatever the two account-wide files
   above say. See "One platform on another command-line PHP" below.

### How Instant PHP-CLI Switching Works

In addition to the `cli.info` file, BOA supports **instant PHP-CLI switching** through **specific configuration files** located in `~/static/control/`. The filenames of these configuration files dictate the PHP version to use, and their content is irrelevant. This enables you to switch the PHP-CLI version for Drush, Composer, and other CLI operations, including Ægir tasks, instantly. The platform builds you request via `platforms.info` follow the marker too — each build resolves it once, when its run starts (on accounts force-pinned to PHP 5.6 for `path_alias_cache` the pin outranks any marker for builds).

> **Reminder:** Instant PHP-CLI switching applies to the commands you type in your limited
> shell logins (`oN.ftp`, a platform developer login) and to your Ægir tasks. It only
> applies to CLI operations — it does not affect PHP-FPM. See the prerequisite section above.

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

**Note:** `cli.info` is read by the shell wrapper on every command as well, so a new value in it applies to your next Drush or Composer run; the background helper that runs every three minutes then re-pins the account's own Drush copy and the Ægir task runner to it, and rewrites `cli.info` to the nearest installed version when the one you named is not installed (until then your commands run on the server's default PHP). The marker files exist for a temporary override you can drop again without editing your default.

### Supported PHP-CLI Versions:

- 8.5, 8.4, 8.3, 8.2, 8.1, 8.0, 7.4, 7.3, 7.2, 7.1, 7.0, 5.6

**However:** Some older PHP versions may no longer be available on your system, because BOA automatically deactivates versions not used by any hosted site. If you need to restore some older PHP version previously available, please open a support ticket with your BOA host, or, if you have root access, run `barracuda php-idle enable` command. If you want to re-install all supported but disabled PHP versions, please run `barracuda up-lts php-max` command. For more details, run `barracuda help` command.

### Important Notes:

- The instant switch files' **content is irrelevant** — what matters is the **filename**.
  These files can be empty or contain any content.
- The system will automatically select the **highest PHP version** based on the filenames of
  the switch files. No need to remove lower-version files.
- The `cli.info` file serves as the **default** PHP-CLI version when no instant switch files
  are present, and it **must contain a valid PHP version** in its content (e.g., `8.1`). A
  value naming a version that is not installed runs your commands on the server's default
  PHP until the background helper corrects the file on its next pass.
- This smart feature, similarly to the classic `~/static/control/cli.info`, depends on the
  BOA special shell wrapper. The wrapper is the server's `/bin/sh`: it runs the commands
  typed in the limited shell logins (`oN.ftp`, a platform developer login) and every Ægir
  task on the account. It reads these
  control files to determine which PHP-CLI version to use — a command that does not go
  through it (typed in a bash shell as `oN`) ignores the control files and runs drush
  against the system default PHP version.
- The one exception is the platforms build requested via `platforms.info`: the build
  machinery resolves the switch files itself, once per run, so it honours them even
  though it never passes through the shell wrapper.
- The wrapper is additionally temporarily deactivated during both barracuda and octopus
  upgrades to not interfere with complex procedures which depend on system dash shell. For
  this reason any Drush or Composer command you execute in the limited shell account while
  barracuda or octopus upgrade is running will revert to the version defined in the
  system-wide `/root/.barracuda.cnf` file.

### Example of `cli.info`:
```
8.1
```
This version will be used by default if no instant switch files (e.g., `php83.info`) are detected.

### One platform on another command-line PHP: `cli-per-platform.info`

`cli.info` and the `phpNN.info` switches choose one PHP-CLI version for the whole account:
your shell, Composer and every Ægir task. An account that hosts old and new Drupal cores
side by side cannot pick one version that suits both. A Drupal 7 site older than 7.79 and
any Drupal 8 site stop on a PHP 8 fatal, while a Drupal 10 or 11 platform needs PHP 8.1 or
8.3 and newer.

`~/static/control/cli-per-platform.info` gives a platform its own PHP-CLI version. One line
per platform: the platform folder, a space, the version.

```
d7-legacy 7.4
platforms/drupal-8.9 7.4
```

**The rule:** anything that runs on a listed platform uses that platform's line; everything
else uses your `phpNN.info` switch, else `cli.info`. "Anything that runs on the platform"
means:

- `drush`, `vdrush`, `bee` and `composer` in your shell, when you work inside the platform
  folder or aim at one of its sites (`drush @site ...`, `--root`, `composer -d`);
- every Ægir task on the platform or on one of its sites: Verify, Backup, Clone, Migrate,
  Flush all caches and the rest. A Clone or Migrate target runs on the TARGET platform's
  line, or on the account-wide files when the target platform has none.

In the shell that holds for the command a line starts with (a leading `cd DIR &&` is fine).
A `drush` behind a pipe or after another command runs on the server's default PHP, whatever
the control files say, so start the line with it.

A platform line **outranks the `phpNN.info` switch**. Renaming `php74.info` to `php84.info`
to work on your Drupal 10 platform no longer moves the Drupal 7 platform you listed. The
Ægir control panel itself never takes a line: it follows `phpNN.info`, else `cli.info`.
PHP-FPM (the web) is never changed by this file. Plain `php` / `phpNN` commands are not
changed either.

How to write the folder:

- relative to `~/static`, as above (`~/static/d7-legacy` works too), or pasted as the
  platform's **Publish path** from the control panel (`/data/disk/oN/static/d7-legacy`); a trailing `/web`, `/docroot` or
  `/html` is dropped, so a Composer platform is listed by the folder that holds its
  `composer.json`;
- a folder covers everything under it; if two lines match, the longer folder wins, and for
  the same folder the last line wins;
- a platform your host ships to your account is written as it appears in your `~/distro`
  folder (`~/distro/002/drupal-7.105.2-prod`), or by its Publish path; a shared one under
  `/data/all/...` by its full path.

The file is read on every command; nothing needs to be restarted, and BOA never writes to
it. A line that cannot apply is ignored and named in a `WARNING` on every drush, vdrush,
bee or Composer command you run, and in the log of every Ægir task on the account: a site
name instead of a folder, a folder that does not exist, or a version that is not installed
on the server.

You can see the choice at any time:

- in your shell, a `NOTE: command-line PHP 7.4 for static/d7-legacy (cli-per-platform.info
  line 1 (outranks php84.info))` on stderr whenever a line overrides your account-wide
  version;
- in the Ægir task log, a line such as `Command-line PHP 7.4.33 for @old.example.com
  (static/d7-legacy): cli-per-platform.info line 1 (outranks php84.info)`.

### Refused before the PHP starts

On every account, with or without `cli-per-platform.info`, a drush command or Ægir task
whose Drupal core cannot run on the PHP chosen for it is refused before the PHP starts,
instead of dying half-way on a PHP fatal:

- a site on Drupal 7 older than 7.79, or on any Drupal 8, on PHP 8.0 or newer;
- a codebase whose `vendor/composer/platform_check.php` needs a newer PHP than the one
  chosen (Drupal 10 needs 8.1, Drupal 11 and site-local Drush 13 need 8.3).

The message names the PHP, the file that chose it and the line that would fix it, e.g.
`Refused before Drupal starts: @old.example.com is Drupal 7.78 (static/d7-legacy), which
cannot run on PHP 8.0 or newer. This would use PHP 8.4, chosen by php84.info. Fix: add
the line "d7-legacy 7.4" to ~/static/control/cli-per-platform.info (or switch back to
php74.info).`

A Clone or Migrate is checked for its target before the safety copy starts. A platform
task, which boots no site, gets the Drupal 7 or 8 text as a warning and runs; a
`platform_check.php` floor refuses it too, because Drush stops at that check whatever it
runs. Commands that never load the codebase (deleting a backup file, the `version` and
alias listing of the server's Drush 8) run as before; `help` can boot the site, so it is
judged like any other command. Composer is never refused, because it is the tool that
repairs `vendor/`.

A tool floor never overrides a platform line: Drush 10/11 on a platform listed below PHP
8.1 is refused, not raised.

Composer resolves packages for the PHP it runs on, not for the PHP-FPM that serves your
site. When `install`, `update` or `require` runs on a newer PHP than a site on that platform
is set to in `fpm.info` or `multi-fpm.info`, and `composer.json` sets no
`config.platform.php`, Composer prints a `WARNING` with both versions. A package that needs
the newer PHP would make that site answer every request with HTTP 500 "Composer detected
issues in your platform". Run Composer on the site's version (a line in
`cli-per-platform.info`) or set `config.platform.php`.

---

## Drush Management in BOA

Drush is the primary tool for managing Drupal sites within BOA, allowing you to perform tasks such as installing sites, cloning sites, or migrating them between Platforms, perform database updates, cache clearing etc. Drush integrates seamlessly with BOA’s PHP-CLI management, ensuring that the correct PHP version is always used.

### Key Highlights:

1. Ægir no longer removes local Drush from any platform.
2. Site-local Drush can be invoked using `vdrush`.
3. PHP-CLI version switching for Drush and Composer is instantaneous using the **instant switch configuration files**.
4. Using standalone Drush versions newer than version 8 is deprecated.
5. Drush 8 remains available as `drush8` or simply `drush` — on a Drupal 8+ site for
   read-only commands only (`uli`, `status`).
6. Drush 10 is available as standalone `drush10`.
7. Drush 11 is available as standalone `drush11`.
8. Drush 12 or newer is available only as **site-local**, invoked via `vdrush`.
9. It is important to review specific **caveats** for managing Drush versions further below.

### Contributed-Module Drush Commands

For security, BOA restricts loading of contributed-module Drush extension files
(`*.drush.inc`) when Drush runs under the **Ægir backend**, so that site code cannot
execute as the privileged Ægir user. The full rationale and the host-side controls
are described in [SECURITY.md](SECURITY.md).

**This restriction does not affect your own CLI sessions.** When you run Drush as the
`oN.ftp` limited-shell account — which, as stressed above, is the account you should
always use — your site's contributed-module Drush commands (for example `civicrm`,
`elysia-cron`, or any other module-provided command) are discovered and run normally.
That is Drush 8 on Drupal 6/7 sites; on a Drupal 8+ site the same commands run
through the site's own Drush, `vdrush` (see below).

If core commands such as `drush @alias cc all` work but a contributed command like
`drush @alias elysia-cron run somecron` is *not recognised*, the usual cause is
running Drush in a bash shell as `oN` (root's `su -s /bin/bash - oN`) instead of as
`oN.ftp`: the `oN` account is an Ægir backend identity, so the filter applies there. Run it
as `oN.ftp` and the contributed commands will load. If you instead need a contributed command to run from
an **Ægir backend task** (such as backend-mode cron), ask your host to enable it for
your instance — see [SECURITY.md](SECURITY.md).

### Update Commands in the Limited Shell

Code and database updates are usually driven through Ægir (a **Verify** or **Migrate**
task), but you can also run them from the `oN.ftp` limited shell.

On a **Drupal 8+** platform, use the site-local `vdrush` (see below) for anything that
changes a site — updates, a cache rebuild, enabling a module.

The system `drush` (Drush 8) starts a Drupal 8/9/10/11 site only while its platform is
locked, and there it runs read-only commands alone: `drush @site-alias uli` and `drush
@site-alias status` answer (the control panel's one-time login links on Drupal 8+ come from
the same Drush 8). Every other Drush 8 command on a Drupal 8+ codebase is refused in the
limited shell, with a pointer to `vdrush`.

On legacy Drupal 6/7 sites Drush 8 runs everything as before, `drush @site-alias updb` (or
`updatedb`) included.

A platform developer login (`oN.<client>-dev`) and the main `oN.ftp` login can run
`checkmyperms` to see which platforms the developer login reaches, why a platform carrying
the client's sites is not reached, the Drush window, and which Drush to use where.

---

### Site-Local Drush is Preserved and Fully Supported

In BOA, Ægir no longer removes the local copy of Drush from platforms during the 'Platform Verify' task. Instead, it locks permissions on the `vendor/drush` directory if present.

This change allows you to easily unlock the local Drush using a new task available on the platform node in the Ægir control panel named 'Unlock Local Drush'. This task is now a required step before you use local `vdrush` or run any updates with `composer` on the command line.

When you are done, re-lock the platform with the new 'Lock Local Drush' task — a lighter, targeted alternative to a full `Platform Verify` for restoring Drush 8 compatibility. Both tasks are idempotent: re-running 'Lock Local Drush' on an already-locked platform, or 'Unlock Local Drush' on an already-unlocked one, is a harmless no-op.

#### Steps to Use Site-Local Drush:

> **Important:** All steps below must be performed as `oN.ftp` under the BOA limited shell,
> not in a bash shell as `oN` (root's `su -s /bin/bash - oN`). A bash shell as `oN` gives the
> wrong PHP environment and `vdrush` will not work correctly. If `vdrush` has not worked for
> you in the past, this is the most likely reason.

1. Run the 'Unlock Local Drush' task on the site's Platform in Ægir.
2. Connect to your server as `oN.ftp` (not `oN`) using SSH.
3. Find the correct Drush `@site-alias` with the `drush11 aliases` command.
4. Switch to the Platform app root where `vendor` exists using `cd`.
5. Run `vdrush --version`. If the codebase has no site-local Drush, install it with `composer require drush/drush` ONLY when the codebase carries no Composer patches (`extra.patches` / `extra.patches-file` in composer.json, or `cweagans/composer-patches` in composer.lock, as the distribution platforms do) and its lock accepts the box's PHP CLI (`composer check-platform-reqs`): on a patched codebase the require makes composer-patches delete every patched package before re-resolving, and they come back unpatched or not at all. Provision's own lock/unlock steps refuse the require in exactly those two cases.
6. Use `vdrush @site-alias updbst`, `vdrush @site-alias updb`, etc.
7. Re-lock the platform with the 'Lock Local Drush' task (or a full 'Platform Verify') to restore compatibility with Drush 8.

Re-locking a platform unlocked earlier, by that task or by a Verify, also rebuilds every Drupal 8+ site on it with Drupal core's own rebuild. A site whose service container the local Drush compiled (a module installed or removed, a recipe applied) could not run on that container once the local Drush is locked away, so the rebuild replaces it. In the task log, `REBUILD/RELOCK` lines open and close the run, with one `REBUILD/CORE` rebuild per site between them.

The nightly maintenance never locks or unlocks a platform: one you unlocked stays unlocked, overnight included, until you run 'Lock Local Drush' or a Verify locks it, and that lock then runs the rebuild above.

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
- On every Ægir / Octopus upgrade, every platform carrying an enabled site is automatically verified and thus local Drush is by default locked again on those platforms. A platform with no enabled site is verified on its next use instead (a platform task, a site installed on it, the next platform build), and only then is its local Drush locked again.

### Stop Using Standalone System Drush 10 and 11

Why is using standalone system Drush other than Drush 8 deprecated, even if still possible?

All post-8 Drush versions up to 11 could theoretically be used as standalone (on command line but not with Ægir) if their numerous dependencies matched the managed Drupal site codebase.

However, most of the time you will find that some dependencies shared by Drupal and Drush 10+ will clash if you try to use Drush in the standalone, system mode, because Composer can’t track their compatibility when you use Drush not included in the Drupal platform's own codebase.

This makes using standalone system versions of Drush 10+ a very frustrating experience and sometimes even impossible.

Please add local Drush to your Drupal codebase with Composer and use it instead of system-wide `drush10` and `drush11` to avoid headaches.

BOA still provides standalone `drush10` and `drush11`, though, because we still need them to convert Drush 8-type site aliases into Drush 10+ type site aliases, but otherwise these standalone Drush versions are of little use.

By the way, due to constant dependencies versions updates, you could get pretty different versions of the same Drush 10+ release installed depending on *when* you have installed it. Sometimes they will be too old and sometimes too new for the Drupal codebase in question. This makes using them as standalone a completely unpredictable mess.

That’s also why Drush 12 has been officially announced as the first version which can’t be used as standalone at all — no matter how hard you would try.

