# Troubleshooting Common Ægir Workflow Issues

This guide addresses common issues that may arise when working with Ægir, Drush, and Composer, and outlines steps to resolve them.

### 1. **Task Failure: Error - Declaration of `Drupal\Core\Logger\LoggerChannel`**

This error typically shouldn't occur in any `site-task` if you have run `Platform Verify + Lock Drush` (or the lighter `Lock Local Drush`) before executing other tasks like `site clone`, `site migrate` or `site verify`. The `Unlock Local Drush` task is required for `site-local` Drush or Composer to work on the command line, after which the platform must be re-locked before running other Ægir tasks. Forgetting to re-lock, or other underlying issues, may cause tasks such as `site clone`, `site migrate` or `site verify` to fail with the PHP error.

The `Lock Local Drush` and `Unlock Local Drush` tasks are themselves idempotent — re-running either on a platform already in that state is a harmless no-op, not an error.

**Resolution Steps:**

If a task fails due to this error, it is crucial to follow the **full recovery cycle** to bring the platform or site back into a working state. The recovery process involves the following steps:

1. **Platform Verify + Lock Drush:**
   Start by running `Verify + Lock Drush` task to ensure the codebase is ready for `site-tasks`.

2. **Unlock Local Drush:**
   Execute `Unlock Local Drush` to remove any codebase permissions locks and un-patch Drupal core.

3. **Platform Verify + Lock Drush Again:**
   After unlocking Drush, run `Platform Verify + Lock Drush` once more to finalize the recovery.

This full cycle is necessary because certain tasks in Ægir may patch or unpatch the core on the fly or adjust file permissions. When an issue like a PHP version mismatch or a codebase error occurs, the platform can go out of sync, requiring multiple steps to fully restore it.

By following this process, you ensure that the platform and site are properly aligned, allowing future Ægir tasks to succeed.

**What the web reads while a platform is locked.** While any Drush 8 copy on the server still binds the untyped psr/log (see below), the lock keeps the codebase's psr/log package and four core logger files (`RfcLoggerTrait`, `LoggerChannel`, `DbLog`, `SysLog`) untyped, as that Drush needs. Web requests and the cache rebuild do not read those: the lock keeps stock copies at `vendor/psr/._orig_core`, beside the genuine psr/log at `vendor/psr/._orig_log`, and each Drupal 10 or 11 site's `settings.php` loads the stock classes from them.

So a module's own logger written for the typed psr/log works on a locked platform. A platform locked earlier gets the copies at its next Verify (`CORE/STOCK stock copies of the core logger files kept at ...` in the task log), and a site uses them once its `settings.php` is next written. A platform whose core came with only some of the four files de-typed (the Drupal 10.0.11 catalogue build) is finished by its next Verify one file at a time and gets its copies in the same Verify; its Unlock, and so the update window of a Restore there, works again.

A custom logger written against the untyped core, with a `log()` that has no `: void`, needs that return type from then on; it already failed whenever the platform was unlocked.

**A Drush 8 that binds the typed psr/log.** On PHP 8.0 and newer, Ægir's own Drush 8 binds psr/log 2.0 before anything else. Its interface takes the typed message that stock Drupal 10 and 11 core and every logger written for psr/log 3 declare, and it still accepts the untyped loggers of Drush itself and of Drupal 7 to 9.

Once every Drush 8 copy on the server carries it (the system copy, the master's and the account's own), the lock leaves the codebase's psr/log and the four core logger files stock: it only locks the site-local Drush and patches the console. A platform locked earlier keeps the untyped lock until it can be converted without a single failed request, and the first task that locks it after that gives it back its genuine psr/log and stock core files and removes the copies at `vendor/psr/._orig_core`.

PHP-FPM keeps each compiled PHP file and checks it against the disk again only after a while: a minute for most requests, three minutes for a request under `/civicrm` (BOA's global settings raise it there), or as long as a site's own settings set with `ini_set('opcache.revalidate_freq', ...)`. A site that loaded the untyped files from the codebase shortly before a conversion could pair an old file with a new one and answer 500 until then.

The lock therefore converts a platform only when no site it serves can still have loaded those files: the stock copies of its core are in place, every served site under its `sites/` has a `settings.php` with the block that loads them, and five minutes have passed since the last change that could have had a site load them from the codebase.

Those changes are a `settings.php` written, the copies or the pristine psr/log put in place, a site directory added to or removed from `sites/` (Install, Clone, Delete, Migrate, a rename), and a site disabled. A disabled site is served a static page and runs no PHP, so its `settings.php` does not count; once enabled again it counts like any other site.

When a site's `settings.php` or `local.settings.php`, the platform's `sites/all/platform.settings.php` or `sites/all/settings.php`, or the server's `/data/conf/settings.global.inc` or `/data/conf/override.global.inc` sets `opcache.revalidate_freq` above 180 as a number, the wait is that many seconds plus two minutes instead; a value those files compute is not read.

Every task that reads the lock of a platform still on the untyped lock, or writes a site's `settings.php` there, notes the longest such value at `vendor/psr/._orig_core.freq` where the lock keeps the pristine psr/log or the stock copies, whether or not every Drush 8 copy binds the typed psr/log yet. The noted value counts until the platform converts, also once the site that set it is gone. A site removed before any such task read its value is not counted, as with a site removed before the Ægir backend that writes the note was installed.

The task that creates the note starts the wait again. A task that raises a value already noted does not; the longer wait then counts from the last change before it.

The conversion then changes first the three core files no site reads at that moment, and renames the psr/log package and `RfcLoggerTrait.php` into place right after each other, each file with a new modification time, so PHP-FPM compiles them again. A site whose logger service is written for psr/log 3 (monolog, raven, or a module's own subclass of a core logger) can then be verified, backed up, restored, cloned and migrated; until its platform converts, it fails in Ægir's Drush.

To convert a platform, verify every enabled site on it, wait five minutes, then run Verify on any of them. A platform locked before the stock copies existed gets them from its first task and converts at a task five minutes later. A directory left under `sites/` by a site that no longer exists (an interrupted Delete) keeps the platform waiting until it is removed. An Unlock puts the files back in place without these checks (the platform's Unlock task, and the update windows of Install, Clone, Migrate and Restore); the lock that closes it then keeps them stock.

The task log says which lock a platform gets: `CHECK/CODE/DRUSH8 =typed=`; `=typed-deferred=` with the reason (`the settings.php of 1 of 3 served sites lacks the block ...`, `... changed 40 s ago ...`, no stock copies yet) while the platform waits; or `=untyped=` while a copy still lacks it, and the lock then works as described above.

With `=untyped=` comes `PSR/LOG the Drush 8 at <copy> binds the untyped psr/log` when the copy that runs the task lacks it, or `PSR/LOG the Drush 8 at <copy> does not bind the typed psr/log yet (no <file>)` when another copy lacks it. On PHP below 8.0 no Drush 8 binds it, and `=untyped=` comes with no `PSR/LOG` line.

A platform whose core logger files do not come off the patch (a file edited by hand), whose genuine psr/log cannot be put back, or whose stock copies cannot be built keeps the untyped lock, with a `PSR/LOG` advisory naming the cause (and a `CORE/STOCK` one for the copies).

The note `vendor/psr/._orig_core.refused` (`CHECK/CODE/DRUSH8 =typed-refused=`) stops further tries until the tree changes. Put the named file back as core ships it, then run **Verify + Lock Drush**. When the copies were the cause (a `vendor/psr` the account cannot write, or a stray file in the way of `vendor/psr/._orig_core.new`), fix that, remove `vendor/psr/._orig_core.refused` and `vendor/psr/._orig_core.failed`, and run Verify: it builds the copies, and the platform converts at a task five minutes later.

### 2. **A site's hash salt**

A Drupal 8 or newer site, and a Backdrop site, keeps its `hash_salt` across Verify, Backup, Restore, Migrate and Rename, so one-time login links, open forms and tokens encrypted with the salt survive those tasks. A clone gets a salt of its own.

To give a site a new salt on purpose, delete the `$settings['hash_salt']` line from its `settings.php` and run Verify. Every outstanding link, form and token of that site is void from then on.

