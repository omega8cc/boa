# Reporting a Vulnerability

**Do not open a public issue for an exploitable bug.** SKYNET keeps every enabled fleet current on a tight cadence, and a public proof-of-concept is live against every production server for the window between disclosure and the next tagged release reaching it.

Report it privately to the maintainers (Omega8.cc) through the contact form at [omega8.cc/contact](https://omega8.cc/contact), or through GitHub's private vulnerability report on this repository: [Report a vulnerability](https://github.com/omega8cc/boa/security/advisories/new). Attach supporting material to the private GitHub report, or ask for a private upload in the ticket; never put it in a secret Gist, which anyone holding the link can read. Public issues that turn out to be security-sensitive are pulled, and you will be asked to refile privately.

Security fixes go to the current 5.x-lts and 5.x-pro releases; older releases get none.

The full policy is under [Security disclosure](https://docs.boa.io/developing/contributing/contributing#security-disclosure) in the BOA documentation.

# Security Considerations for Multi-Ægir Systems

In a multi-Ægir instance system, all instances utilize the same Nginx server. Consequently, installing a site with the same domain on multiple instances can cause conflicts. **The instances are not aware of each other**, so it is crucial to manage the system responsibly.

It is **imperative** to never grant anyone access to the Ægir **system user** on any Octopus instance. This user has near-root access to **all** sites databases hosted across **all** Octopus instances on the same BOA server. Only provide **restricted shell** access accounts and **non-admin** Ægir control panel accounts to end-users.

# Security Considerations for Node/NPM Access

Given that `node` can be exploited to bypass Limited Shell and pose a significant security risk to the BOA system, it should not be enabled on any BOA system with multiple `lshell` users. Consequently, Node/NPM support is not enabled in BOA by default. It is enabled when the empty control file `/root/.allow.node.lshell.cnf` exists, or automatically when any Octopus instance on the box is of type PHANTOM, CLUSTER, ULTRA or MONSTER; on every other box `node`, `npm`, `npx` and `scp` are stripped from the limited shell's command lists on every pass.

In hosted BOA environments, Node/NPM support is available only on dedicated systems such as Phantom and Cluster.

# Security Considerations for Running PHP by Name

Outside a Composer run, only members of the hand-assigned `ltd-shell-more` group run PHP by name. In the limited shell lshell offers them `php56`, `php74` and `php81` to `php86`; any other account typing one gets lshell's own refusal.

A tool the account runs can also hand `/bin/sh` a command line, an npm script for example. There BOA's `/bin/sh` wrapper refuses, for every account outside the group, a command whose program is a PHP interpreter (`php`, `phpNN`, `php-cli`, `phpdbg` or a path to one) with "Running PHP directly is not available on this account."

Composer is the exception. Inside a Composer run every account runs PHP by name: an `@php` script entry, a compile task of CiviCRM's packages, a `php` line in the project's own `composer.json` scripts, or a tool one of those starts. Composer already runs its plugins and PHP callback scripts inside its own process, so refusing its children stopped real builds without closing anything. Outside a Composer run, PHP typed in the shell or started by any other tool stays refused.

The wrapper recognises the run by an ancestor process of the same account, up to eight steps up, whose program is one of the server's PHP builds (`/opt/phpNN/bin/php` or `/usr/bin/php`) running `/usr/local/bin/composer` (or BOA's `/usr/bin/composer` link to it), whether the wrapper started that Composer or it was started by its path. A script line such as `XDEBUG_MODE=off php vendor/bin/phpunit` is still refused, since the wrapper refuses a `NAME=value` word in front of `php`, and the refusal fails the Composer script; set the ini value with PHP's own `-d` option instead (`php -d xdebug.mode=off vendor/bin/phpunit`).

Drush, vdrush, bee and Composer keep working: the wrapper starts them itself on the PHP version the account chose. A Drush launcher at the head of a line that names an interpreter runs on that version too. A Composer `@composer` entry and `grav composer` run Composer on the PHP they name when it is one of the server's `/opt/phpNN/bin/php` builds. Members keep PHP by name while the box's `/etc/lshell.conf` carries the `phpNN` aliases.

# BOA System Security Features Explained

BOA offers a highly secure hosting environment for Ægir and Drupal sites, featuring comprehensive built-in security monitoring and autonomous attack prevention systems. Below is a list of key features that collectively provide robust protection for all hosted sites. For additional information, consider reading about [running performance or load tests](https://docs.boa.io/using/protecting-your-site/load-testing).

1. **Encrypted Connections**: Account access is restricted to SSH, SFTP (FTP over SSH), and FTPS (FTP over SSL).
2. **Restricted PHP Scripts**: Only recognized Drupal PHP files are allowed in the BOA secure environment. The web server does not have write access to the website codebase, blocking common attack vectors even for sites with otherwise vulnerable codebases.
3. **Web Server Monitoring**: IP addresses exhibiting DoS-like activity are temporarily blocked for 15 minutes and permanently blocked after repeated offenses. You can [whitelist your IP on the fly](https://docs.boa.io/using/when-somethings-wrong/blocked-or-slow) by maintaining an active SSH connection.
4. **Firewall Monitoring**: Repeated failed login attempts for SSH, SFTP, or FTPS result in temporary one-hour blocks, escalating to permanent blocks. Whitelisted IPs are not exempt if abuse is detected.
5. **Load Management**: The web server may be temporarily disabled during high system loads due to undetected DoS attacks. The web tier resumes only after `_RESUME_HOLD_PASSES` (default 3) consecutive readings below the resume threshold, which is the maximum load times `_RESUME_FRACTION` (default 0.8): a single calm reading does not release it.
6. **Port Scan and Flood Protection**: Detected port scans or floods result in temporary one-hour blocks, escalating to permanent blocks after repeated offenses. False positives are detailed in our [How Firewall Works article](https://docs.boa.io/using/when-somethings-wrong/blocked-or-slow).
7. **Per-Plan Resource Limits**: PHP-FPM runs each account with a capped worker pool, so a single site cannot monopolize the server or destabilize its neighbours during a traffic spike. Shared plans keep a fixed per-plan worker limit; dedicated plans size their pool dynamically from available RAM and CPU.
8. **Perfect Forward Secrecy and HTTP/2**: All HTTPS services utilize Perfect Forward Secrecy and HTTP/2 for enhanced security and speed. Non-supportive browsers default to classic HTTPS with SSL and Perfect Forward Secrecy.
9. **PHP Error Protection**: PHP errors are not displayed in browsers. Debugging can be performed using protected dev domain aliases.
10. **Password Expiration Policy**: SSH, SFTP, and FTPS passwords expire every 90 days and must be updated, even if SSH keys are in use.
11. **Restricted Admin Access**: Admin account access (uid=1) is unavailable in Ægir to prevent potential misuse. Non-admin main account access provides sufficient privileges for safe management in a multi-Ægir environment.
12. **Restricted System Binaries Access**: BOA modifies access permissions to system binaries and commands that could potentially be used as attack vectors by web shells and other intrusion methods, significantly limiting damage potential even for sites running older Drupal versions.
13. **Automatic OS Security Updates**: On modern systems, operating-system security updates are applied automatically between BOA upgrades, so critical patches do not wait for your next manual run. Updates are security-only, and a new security kernel is activated through BOA's own graceful reboot flow rather than an unscheduled reboot. This is on by default and can be turned off with `_SYSTEM_AUTO_SECURITY=NO` in `/root/.barracuda.cnf`.
14. **Root-Owned Shared Code Store**: The shared legacy code store under `/data/all` belongs to root, and root builds what is in it. The shared Drupal 6 and 7 cores and the shared platform trees are each built in a stage directory and moved into place only when every download for it succeeded, so a site never finds one half-built or missing, and a forced refresh of a contrib bundle is fetched the same way and keeps the bundle as it was when a download fails. The platform build that runs as the instance user only reads the store; nothing in it is handed to an account. The first Octopus upgrade that builds platforms fetches the current contrib bundles again (and the bundle a current core links from an earlier serial), builds the current shared cores and trees again and removes every ACL in the store; what it cannot fetch or build is kept as it was and retried by the next upgrade, until all of it is done once. The shared `sites/all` module, library and theme directories stay group-writable by design.
15. **PHP-FPM Pool Sockets Answer Only the Web Server**: every PHP-FPM pool socket, the master `www` pools included, is owned by `www-data` with mode `0600`, so only nginx and root can send a pool a FastCGI request. A member of `www-data` — every account's shell users and every pool's own workers — cannot hand another account's pool, or a master pool, a script to run as that pool's user. The barracuda pass writes the mode into the shipped fragments (`aegir/conf/php/fpm-pool-common*.conf`) and applies it to the sockets already bound.
16. **Hidden Files and Package Manifests Are Never Served**: the Drupal and Backdrop vhosts answer 404 for any path with a part that starts with a dot, apart from `.well-known/` at a site's root, as Drupal's own `.htaccess` does, and for `composer.json`, `composer.lock`, `package.json`, `package-lock.json` and `yarn.lock` outside the private files under `system/files/`, subdirectory sites and the `/files/`, `/downloads/` and far-future CDN paths included. A checkout's control files, an editor's leftovers or a manifest naming a codebase's exact versions never reach a visitor. A site that must serve such a path can add its own location in `nginx_force_include.conf`.

# Drush Extension (`*.drush.inc`) Loading Restrictions

Drush automatically discovers and loads any `*.drush.inc` extension file present in
a site's modules or themes. On a shared Ægir server this is a privilege-escalation
risk: a client who can modify their site's codebase could drop a malicious
`*.drush.inc` that Drush would then load and execute **as the Ægir backend user**
during a routine task (verify, migrate, cron, and so on) — i.e. with authority over
every site on that Octopus instance. This is the long-standing upstream issue
[#762138](https://www.drupal.org/project/provision/issues/762138).

BOA closes this at the Drush layer. When Drush runs **as an Ægir backend identity**
— the master `aegir` user, or an Octopus instance user `oN` — it refuses to load
`*.drush.inc` files located under tenant-writable paths
(`/data/disk/<oN>/{static,distro,platforms}/…` and the non-BOA parts of
`~/.drush/`). BOA's own Drush extensions (under `~/.drush/{sys,usr,xts}/` and the
`aegir/distro/` tree) and everything on the Ægir Master are unaffected, so ordinary
hosting tasks and all core Drush commands keep working.

The same refusal covers annotated command classes (`*Commands.php`) on those paths,
including the ones a platform carries in its own `drush/Commands/` directories
(beside the docroot, inside it, or under `sites/all/drush`): from Drush 8.5.12 the
backend never loads them either.

**The restriction does not apply to limited-shell sessions.** When a user runs
Drush themselves in a limited-shell login — `oN.ftp` or a platform developer login
(`oN.<client>-dev`), the logins they are meant to use for all CLI work (see
[DRUSH-CLI.md](DRUSH-CLI.md)) — the filter is skipped entirely and their site's
contributed-module Drush commands load normally. Running in such a login is not an
escalation (the user already owns that account), so there is nothing to guard
against there. BOA makes this distinction from the effective
system user of the Drush process, which a client cannot forge.

## Allowing specific extensions for the Ægir backend

A few contributed modules legitimately provide Drush commands that the Ægir backend
itself may need to run. These are enabled per Octopus instance with an empty control
file under `/data/conf/`, following the same convention as BOA's other opt-in
restrictions (such as the Node/NPM `lshell` control file above):

| Control file | Effect |
|---|---|
| `/data/conf/<oN>_civicrm.txt` | Allow the backend to load CiviCRM's Drush commands (`civicrm.drush.inc`, `cv.drush.inc`, `civicrm_drush.drush.inc`) for that instance's CiviCRM sites. |
| `/data/conf/<oN>_elysia_cron.txt` | Allow the backend to load `elysia_cron.drush.inc` for that instance, so backend-mode cron (`hosting_cron_use_backend`) keeps Elysia Cron's fine-grained schedule instead of falling back to core cron. |

Replace `<oN>` with the Octopus instance user (for example `o1`). The file's content
is irrelevant — only its presence matters. Create it as `root`:

```bash
touch /data/conf/o1_elysia_cron.txt
```

Backend-run Drush cron is a legacy path: BOA does not use Drush-based cron on
Drupal 8+ (it is incompatible), so the `elysia_cron` opt-in matters only for older
sites that both use Elysia Cron and have `hosting_cron_use_backend` enabled. It is
never enabled automatically — you decide, per instance, whether to grant it.

## Lifting the restriction entirely (single-tenant servers only)

If you are the **only** tenant on the server and accept the risk, you can turn the
filter off completely — for every identity, including the Ægir backend — with one
global control file:

```bash
touch /data/conf/drush_extension_filter_disabled.txt
```

This restores stock Drush `*.drush.inc` loading everywhere and **re-opens
[#762138](https://www.drupal.org/project/provision/issues/762138)** on that server.
Never use it on a server that hosts sites for more than one party. On multi-tenant
servers the per-instance opt-ins above are the correct tool — and because
limited-shell (`oN.ftp`) sessions are never filtered, ordinary client CLI use needs
no opt-in at all. Remove the file to re-enable the protection.

## Verifying the filter

To confirm on a real box that the protection holds for the Ægir backend while
limited-shell (`oN.ftp`) CLI use is unaffected, follow the step-by-step runbook in
[DRUSH-FILTER-TESTING.md](DRUSH-FILTER-TESTING.md).

# PHP Function Restrictions

Every PHP-FPM pool disables the same functions: the system-level `disable_functions` list in each version's `php.ini`, plus the pool template's own list, which adds `passthru`. There is no per-host or per-instance list.

The pools of one PHP version run under one FPM master and share its opcache. PHP 8.4 and newer compile a call to a built-in function as that function's position in the function table, and every disabled function shifts the positions after it. Two pools that disabled different functions would therefore run each other's compiled code against a different table: a shared file (a module under `/data/all`, BOA's global settings include) compiled in one pool calls the wrong built-in function in the other, and the site or the control panel there fails with a blank page.

BOA no longer applies a `_PHP_FPM_DENY` line: the next Barracuda and Octopus upgrade delete it from `/root/.barracuda.cnf` and `/root/.USER.octopus.cnf`. Within minutes the system worker puts the template's list back into any pool of an instance that carries another one, and the next Barracuda upgrade writes the `wwwNN` pools of the Ægir Master Instance again from their template. What site code can start through the functions that stay enabled is limited by `_STRICT_BIN_PERMISSIONS` below.

## SQLite extension loading on PHP 8.4 and newer

PHP 8.4 added `Pdo\Sqlite::loadExtension()`, which loads a native shared object from any path: neither `open_basedir` nor `sqlite3.extension_dir` applies to it, so it would let site code run native code even where every function that starts a process is disabled. BOA builds PHP 8.4 and newer without that one method, and the next Barracuda upgrade rebuilds an installed 8.4 or newer version that still has it.

The `pdo_sqlite` driver, the `sqlite:` DSN, `Pdo\Sqlite::createFunction()` and the `SQLite3` class keep working, and `SQLite3::loadExtension()` stays off because BOA leaves `sqlite3.extension_dir` unset.

## Session upload progress is off

Every PHP version, 5.6 through 8.6, runs with `session.upload_progress.enabled = Off`. PHP's own default is On: the session extension then watches every multipart POST for a `PHP_SESSION_UPLOAD_PROGRESS` field and writes the upload's progress into the visitor's session before the site's code runs. No CMS BOA hosts reads that data; Drupal and Backdrop show upload progress through the `uploadprogress` extension, which stays enabled.

The Off line ships in the `php.ini` templates of every version, the FPM file (`/opt/phpNN/etc/phpNN.ini`) and the command-line one (`/opt/phpNN/lib/php.ini`). Each Barracuda pass copies the templates over the live files, so the system agent (`BOA.sh.txt`, every 5 minutes, also with `_SKYNET_MODE=OFF`) checks both files of every version on each run and puts the line back where a pass from an older tree brought PHP's default back.

It reloads that version's FPM master only after the master's own configuration test passes; a master that fails the test keeps serving, and the reload is retried on every run. Each change is logged in `/var/log/boa/php-upload-progress.log`.

A site cannot turn it back on: the directive cannot be changed with `ini_set()`, BOA disables `.user.ini` files, and there is no Apache `.htaccess` layer.

## Fatal error backtraces off on a PHP 8.5 or 8.6 build without the fix

PHP's October 2026 security fix came with PHP 8.5.12 and 8.6.0RC4. For a build without it, PHP's advisory gives `fatal_error_backtraces = Off` as the setting that closes one way to reach the bug. A box the PHP security floor holds back (a staged major OS upgrade, three passes that changed nothing, `_SKYNET_MODE=OFF` with an older launcher) can still run an older 8.5 or 8.6 build.

The system agent checks the installed 8.5 and 8.6 builds on every run and, on one older than 8.5.12 or 8.6.0RC4, keeps that line in both of its `php.ini` files the same way it keeps the upload progress line: it puts the line where PHP's commented default is, and reloads that version's FPM master after its configuration test, logging to the same file. Fatal errors are still logged, without the backtrace. A build with the fix is left as it is, and the `php.ini` templates carry PHP's default.

## Security backports for older PHP releases

PHP fixes security bugs only in its supported versions, while BOA still builds 5.6, 7.0 to 7.4, 8.0 and 8.1. When a fix matters for those, BOA ships its own backport as `aegir/patches/php-sec/php-<release>-<id>.patch`, made for that exact release. Every build of that release from sources applies it, exactly as written (no fuzz); if a patch does not apply, nothing is built and the build in place keeps serving, with an ALRT line in the pass log.

A build records the patches it carries in `/opt/phpNN/lib/boa-sec-patches`, one id a line. The prebuilt packages are made from the builder mirrors' own barracuda builds, so they carry the patches and the record too. A Barracuda pass rebuilds a version whose record lacks a patch the tree has for its release, and refuses a prebuilt package without it in favour of the source build. To bring every box to the patched build at once, a BOA release names the patch in the PHP security floor (see SELFUPGRADE.md).

PHP 7.4.33, 8.0.30 and 8.1.34 carry `cve-2026-109618-109619`: the PHP security team's own minimal backport of its October 2026 security fix, published for the versions it no longer maintains, taken unchanged from php-src's `PHP-7.4-CVE-2026-109618-109619`, `PHP-8.0-CVE-2026-109618-109619` and `PHP-8.1-CVE-2026-109618-109619` branches.

Every one of these releases also carries `sury-<n>`: the security and bug fixes Debian's PHP packaging (Ondřej Surý, `debian/main/<version>` in the php-team repository on salsa.debian.org) has backported to it since its last release, at his packaging level `<n>` (5.6.40-105, 7.0.33-93, 7.1.33-81, 7.2.34-66, 7.3.33-35, 7.4.33-31, 8.0.30-25, 8.1.34-9).

For 5.6 to 7.3 that includes the October 2026 fix (the PHP security team's 7.4 backport, adapted to each version in his packaging) and the `max_multipart_body_parts` limit. On 7.4, 8.0 and 8.1 the patch applies after `cve-2026-109618-109619`, and its result was checked to equal his own packaging's code.

Only his fixes are taken: his Debian packaging, build and layout changes and his version-check telemetry are left out, and his binary packages are never used.

PHP 5.6 to 7.3 link OpenSSL 3 (`/usr/local/ssl3`), like 7.4 and later, wherever BOA has it; only a box without it builds them with OpenSSL 1.1, which gets no fixes since 2023. A build linked to the other OpenSSL is rebuilt. On them, as on 7.4 and later already, OpenSSL 3 refuses TLS 1.0 and 1.1 and the algorithms it keeps out of its default set (RC4, RC2, MD5 signatures).

PHP 5.6.40 and 7.0.33 also carry `openssl3-pkey-export`, BOA's own fix: `openssl_pkey_export_to_file()` wrote through a file handle it never checked, which OpenSSL 1.1 ignored and OpenSSL 3 crashes on when the path cannot be opened. It now returns false there, as 7.1 and later do.

# Strict Binary Permissions

## Option in `/root/.barracuda.cnf`

Every Barracuda upgrade sets this option to `YES`: PHP functions like `exec`, `shell_exec`, `system`, `proc_open` and `popen` stay enabled in every PHP-FPM pool, and this option limits the binaries they can start.

```ini
_STRICT_BIN_PERMISSIONS=YES
```

**WARNING!** This option is very aggressive and can break any extra service or binary you have installed which BOA doesn't manage and the binary has a system group set to 'root'. BOA will not touch any binary which has a non-root group or has setgid or setuid permissions.

**Recommended setting:**

```ini
_STRICT_BIN_PERMISSIONS=YES
```
