
BOA control files — quick cheat sheet (~/static/control/)
=========================================================

The small plain-text files in this folder let you switch PHP versions,
choose platforms, speed up cloning and more — from your own account, no
root access needed. Create or edit a file, save it, and a background
agent applies the change, usually within a few minutes.

This cheat sheet covers the moves most people need. The full story for
every file lives in the documentation:

  https://docs.boa.io/using                      the guide for your account
  https://docs.boa.io/reference/control-files    every control file, indexed
  https://docs.boa.io/cheat-sheets               all quick-start cheat sheets


Switch PHP versions
-------------------

  echo 8.4 > ~/static/control/fpm.info    the version serving ALL your sites
  echo 8.4 > ~/static/control/cli.info    the version for Drush + shell

Twelve versions are supported, 5.6 through 8.5, but only versions
installed on the server can be used — ask your host if one you need
is missing. Changes apply within about three minutes.

Per-site exceptions go one per line into multi-fpm.info — the main
domain, a space, then the version. Sites not listed keep following
fpm.info:

  foo.com 8.5
  old.com 7.4

Need your shell on another version right now? Create an empty marker
like php83.info here and your next shell/Drush command uses it
immediately. The marker also steers the platform builds you request
below — each build reads it once, when its run starts.

Drush, Composer and bee all follow cli.info (or your phpNN.info
marker) in the shell.

  Docs: https://docs.boa.io/using/tuning/php-version


Install or refresh platforms (no root needed)
---------------------------------------------

  1. Put the platform symbols you want in ~/static/control/platforms.info
     (UPPERCASE, separated by spaces or newlines), or the keyword ALL
     to always get everything:

       DE4 CMS BDR
       (or)
       ALL

  2. touch ~/static/control/run-upgrade.pid

Your Ægir instance upgrade starts within a few minutes; the trigger
file is removed automatically. Without platforms.info the trigger is
ignored. Note that platforms.info REPLACES the default list — pinned
symbols mean you skip distributions added in future releases, while
ALL never skips anything.

Platform symbols:

  Backdrop (built by default; a server can opt out)
    BDR — Backdrop CMS prod/stage/dev

  Drupal 11.4
    DE4 — Drupal 11.4 prod/stage/dev
    CK3 — Commerce v.3
    CMS — Drupal CMS
    LGV — LocalGov
    THR — Thunder
    VBX — Varbase 10

  Drupal 11.3
    DE3 — Drupal 11.3 prod/stage/dev
    FOS — farmOS
    OCS — OpenCulturas

  Drupal 11.2
    DE2 — Drupal 11.2 prod/stage/dev

  Drupal 11.1
    DE1 — Drupal 11.1 prod/stage/dev

  Drupal 10.6
    DX6 — Drupal 10.6 prod/stage/dev
    OFD — OpenFed
    OPG — Opigno LMS
    SOC — Social

  Drupal 10.5
    DX5 — Drupal 10.5 prod/stage/dev

  Drupal 10.4
    DX4 — Drupal 10.4 prod/stage/dev

  Drupal 10.3
    DX3 — Drupal 10.3 prod/stage/dev
    EZC — EzContent

  Drupal 10.2
    DX2 — Drupal 10.2 prod/stage/dev

  Drupal 10.1
    DX1 — Drupal 10.1 prod/stage/dev
    CK2 — Commerce v.2

  Drupal 10.0
    DX0 — Drupal 10.0 prod/stage/dev

  Drupal 9
    DL9 — Drupal 9 prod/stage/dev

  Drupal 7
    DL7 — Drupal 7 prod/stage/dev
    CK1 — Commerce v.1
    UC7 — Ubercart

  Drupal 6
    DL6 — Pressflow (LTS) prod/stage/dev
    UC6 — Ubercart

Older cores need matching legacy PHP versions installed — on hosted
BOA ask your host if you need one enabled.

  Docs: https://docs.boa.io/using/sites-and-platforms/platforms


Fast cloning and migration
--------------------------

Super-fast per-table parallel database dumps are the default — clone
and migrate runs that once took hours finish in minutes. The
trade-off: the site archive keeps no classic single-file DB dump, so
the Restore task cannot use archives made this way. Nightly backups
still cover you, and a Backup task run in classic mysqldump mode
stays restorable.

  touch ~/static/control/MyClassic.info    opt out — classic dumps again
  touch ~/static/control/FastTrack.info    opt in — also skip the verify
                                           tasks run before clone/migrate

Verify-first is the default; to return to it later, create
ClassicTrack.info and delete FastTrack.info.

  Docs: https://docs.boa.io/using/sites-and-platforms/cloning-and-migrating


Unlock your codebase for in-place upgrades
------------------------------------------

Nightly maintenance keeps your platform code owned by the backend
user — day-to-day edits still work via the shared group, but composer
and git upgrades need the owner's rights:

  touch ~/static/control/unlock.info    hand code ownership to your
                                        shell user (next nightly run)
  rm ~/static/control/unlock.info       restore the default protection
                                        (next nightly run)

Back up the codebase yourself first — the Backup task never includes
it. Run composer in the repository root, then WAIT until the PHP and
Nginx caches expire and the sites are proven working BEFORE you run
Verify on the platform: Verify hands ownership straight back, and a
broken platform then stays broken until the next nightly run returns
it to you. An empty skip.info in a platform root excludes just that
platform from the nightly ownership management.

  Docs: https://docs.boa.io/using/deploying-code/in-place-upgrades


When the task queue is stuck
----------------------------

  touch ~/static/control/clear-drush-cache.info

A broken platform build can pause queued tasks for a day or two; this
purges the backend build workspace and Drush caches so tasks flow
again, then removes itself.

  Docs: https://docs.boa.io/using/deploying-code/building-a-platform
  More first aid: https://docs.boa.io/cheat-sheets/when-somethings-wrong


Also available here
-------------------

  run-sftp-password-update.pid — rotate your SSH/SFTP password; the
      new one appears here as new-<account>.ftp-password.txt

  run-php-fpm-reload.pid — graceful PHP-FPM reload, clears APCu
      (higher plans, or ask your host)
      https://docs.boa.io/using/caching/php-opcache-and-apcu

  newrelic.info — your New Relic license key (pairs with a per-site
      INI opt-in)
      https://docs.boa.io/using/extra-services/new-relic

  compass.info — Ruby Gems (Sass/Compass) and NPM (Gulp/Bower)
      tooling for your shell
      https://docs.boa.io/using/deploying-code/dev-workflow

  ip/access.txt — allow or deny visitor IPs for your sites
  ip/user_admin.txt — lock login + admin pages to your IPs
  ai/policy.txt — your AI crawler policy
      https://docs.boa.io/using/protecting-your-site/access-control

  remote_backups/ — off-site backup credentials and config
      https://docs.boa.io/using/backups/mybackup-and-quota

Everything else, indexed: https://docs.boa.io/reference/control-files


A note on INI files
-------------------

Per-site settings (caching, cookies, module opt-outs and more) do not
live in this folder — they go in boa_site_control.ini or
boa_platform_control.ini inside your platform tree:

  https://docs.boa.io/cheat-sheets/control-files


This README is refreshed automatically with every BOA release — edits
made here will be overwritten.
