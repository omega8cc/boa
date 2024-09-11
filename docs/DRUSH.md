# Using Drush on BOA

BOA-5.2.0 introduced significant improvements to Drush usage while maintaining all previously available features.

Here are some highlights, with detailed explanations below:

1. Ægir no longer removes local Drush from any platform.
2. Site-local Drush can be invoked with `vdrush`.
3. The PHP-CLI version for the command line can be switched instantly.
4. Using any standalone Drush newer than version 8 is deprecated.
5. Drush 8 remains available as `drush8` or simply `drush`.
6. Drush 10 is available as standalone `drush10`.
7. Drush 11 is available as standalone `drush11`.
8. Drush 12 is available only as site-local with `vdrush`.
9. It is important to read about the CAVEATS.

## Site-Local Drush is Preserved and Fully Supported

The most significant improvement is that Ægir no longer removes the local copy of Drush from the platform when the 'Platform Verify' task is run.

Instead, Ægir only locks permissions on the `vendor/drush` directory, if present.

This change allows you to easily unlock the local Drush using a new task available on the platform node in the Ægir control panel named 'Unlock Local Drush'. This task is now a required step before you use local `vdrush` or run any updates with `composer` on the command line.

To use site-local Drush, follow these steps:

1. Run the 'Unlock Local Drush' task on the site's Platform in Ægir.
2. Find the correct Drush `@site-alias` with the `drush11 aliases` command.
3. Switch to the Platform root where `vendor` exists using `cd`.
4. Run `vdrush --version` or install it with `composer require drush/drush`.
5. Use `vdrush @site-alias updbst`, `vdrush @site-alias updb`, etc.
6. Run the 'Platform Verify' task to restore compatibility with Drush 8.

## PHP-CLI Version Configuration is Much Smarter

The second most important improvement is that switching PHP version for Drush and Composer on the command line can be instant and since BOA-5.4.0 will affect instantly also the Ægir backend's PHP-CLI version. Here’s how it works:

The classic `~/static/control/cli.info` is still respected on the command line as the default version affecting not only Ægir backend tasks but also Drush — and now also Composer!

But to configure PHP-CLI version to be used on the command line with Drush and Composer (and now also by the Ægir backend), you can also use an independent and new configuration system based on empty control files:

- `~/static/control/php83.info`
- `~/static/control/php82.info`
- `~/static/control/php81.info`
- `~/static/control/php80.info`
- `~/static/control/php74.info`
- `~/static/control/php73.info`
- `~/static/control/php72.info`
- `~/static/control/php71.info`
- `~/static/control/php70.info`
- `~/static/control/php56.info`

**Note:** These files will switch the PHP version used *instantly*, unlike the classic `~/static/control/cli.info` which requires 3 minutes to take effect.

**Also:** The highest version wins if there is more than one such file.

**IMPORTANT:** This smart feature, similarly to the classic `~/static/control/cli.info` depends on the BOA special shell wrapper, which is temporarily deactivated during both barracuda and octopus upgrades to not interfere with complex procedures which depend on system dash shell. For this reason any Drush or Composer command you will execute in the limited shell account while you or your host is running barracuda or octopus upgrade will revert to the version defined in the system-wide `/root/.barracuda.cnf` file.

**However:** Some older PHP versions may no longer be available on your system, because BOA automatically deactivates versions not used by any hosted site. If you need to restore some older PHP version previously available, please open a support ticket with your BOA host, or, if you have root access, run `barracuda php-idle enable` command. If you want to re-install all supported but disabled PHP versions, please run `barracuda up-lts php-max` command. For more details, run `barracuda help` command.

## Caveats

- When using standalone `drush8`, `drush10`, or `drush11`, please use Drush Aliases — we don’t test anything running standalone Drush commands in the site directory anymore — it’s probably an old habit which should be avoided for standalone Drush — also because it may and will clash with local Drush if also present.
- Note that the Drush Alias name for the site with `drush10` is different than for `drush8` — all dots in the site name should be replaced with hyphens and only the last dot before the domain's last extension should be a dot. Example: `drush8 @sub.domain.top.org` becomes `drush10 @sub-domain-top.org`.
- On every Ægir / Octopus upgrade, all platforms are automatically verified and thus local Drush is by default locked again in all existing platforms.

## Stop Using Standalone System Drush 10 and 11

Why is using standalone system Drush other than Drush 8 deprecated, even if still possible?

All post-8 Drush versions up to 11 could theoretically be used as standalone (on command line but not with Ægir) if their numerous dependencies matched the managed Drupal site codebase.

However, most of the time you will find that some dependencies shared by Drupal and Drush 10+ will clash if you try to use Drush in the standalone, system mode, because Composer can’t track their compatibility when you use Drush not included in the Drupal platform's own codebase.

This makes using standalone system versions of Drush 10+ a very frustrating experience and sometimes even impossible.

Please add local Drush to your Drupal codebase with Composer and use it instead of system-wide `drush10` and `drush11` to avoid headaches.

BOA still provides standalone `drush10` and `drush11`, though, because we still need them to convert Drush 8-type site aliases into Drush 10+ type site aliases, but otherwise these standalone Drush versions are of little use.

By the way, due to constant dependencies versions updates, you could get pretty different versions of the same Drush 10+ release installed depending on *when* you have installed it. Sometimes they will be too old and sometimes too new for the Drupal codebase in question. This makes using them as standalone a completely unpredictable mess.

That’s also why Drush 12 has been officially announced as the first version which can’t be used as standalone at all — no matter how hard you would try. We still try, though, because we already have a good track record of making the impossible possible, like hosting Drupal 10 on Drush 8 based Ægir. Watch this space.
