
# Using Drush on Systems Running BOA-5.2.0 or Newer

The BOA-5.2.0 version introduced major improvements to the way Drush can be used while preserving all previously available features.

Here are a couple of highlights, with details explained further below:

1. Aegir no longer removes local Drush from any platform.
2. PHP-CLI version for command line can be switched instantly.
3. Using any standalone Drush newer than 8 is deprecated.
4. Drush 8 is still available as either `drush8` or just `drush`.
5. Drush 10 is still available as standalone `drush10`.
6. Drush 11 is still available as standalone `drush11`.
7. Drush 12 is present but does not work as standalone.
8. Read about CAVEATS, they are important too.

## Site Local Drush is Preserved and Fully Supported

The most important improvement is that Aegir no longer removes the local copy of Drush in the platform once you run the platform Verify task.

Instead, Aegir only locks permissions on the `vendor/drush` directory, if present.

This allows you to easily unlock local Drush with a new task available on the platform node in the Aegir control panel named Unlock Local Drush, which is now a required step before you try to use local Drush or run any update with Composer on the command line.

Since Drush Launcher is no longer supported and working, it has been removed.

We are still working on a replacement for accounts using Limited Shell without Bash access, to make using site-local Drush easier.

## PHP-CLI Version Configuration is Much Smarter

The second most important improvement is that switching PHP version for Drush on the command line is now instant and managed *independently* of the Aegir backend's own PHP-CLI version. Here’s how it works:

The classic `~/static/control/cli.info` is still respected on the command line as the default version affecting not only Aegir backend tasks but also Drush — and now also Composer!

But to configure PHP-CLI version to be used on the command line with Drush and Composer, you can also use an independent and new configuration system based on empty control files:

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

**However:** Some older PHP versions may no longer be available on your system, because BOA automatically deactivates versions not used by any hosted site. If you need to restore some older PHP version previously available, please open a support ticket with your BOA host, or, if you have root access, run `barracuda php-idle enable` command. If you want to re-install all supported but disabled PHP versions, please run `barracuda up-lite php-max` command. For more details, run `barracuda help` command.

## Caveats

- When using standalone `drush8`, `drush10`, or `drush11`, please use Drush Aliases — we don’t test anything running standalone Drush commands in the site directory anymore — it’s probably an old habit which should be avoided for standalone Drush — also because it may and will clash with local Drush if also present.
- Note that the Drush Alias name for the site with `drush10` is different than for `drush8` — all dots in the site name should be replaced with hyphens and only the last dot before the domain's last extension should be a dot. Example: `drush8 @sub.domain.top.org` becomes `drush10 @sub-domain-top.org`.
- On every Aegir / Octopus upgrade, all platforms are automatically verified and thus local Drush is by default locked again in all existing platforms.

## Stop Using Standalone System Drush 10 and 11

Why is using standalone system Drush other than Drush 8 deprecated, even if still possible?

All post-8 Drush versions up to 11 could theoretically be used as standalone (on command line but not with Aegir) if their numerous dependencies matched the managed Drupal site codebase.

However, most of the time you will find that some dependencies shared by Drupal and Drush 10+ will clash if you try to use Drush in the standalone, system mode, because Composer can’t track their compatibility when you use Drush not included in the Drupal platform's own codebase.

This makes using standalone system versions of Drush 10+ a very frustrating experience and sometimes even impossible.

Please add local Drush to your Drupal codebase with Composer and use it instead of system-wide `drush10` and `drush11` to avoid headaches.

BOA still provides standalone `drush10` and `drush11`, though, because we still need them to convert Drush 8-type site aliases into Drush 10+ type site aliases, but otherwise these standalone Drush versions are of little use.

By the way, due to constant dependencies versions updates, you could get pretty different versions of the same Drush 10+ release installed depending on *when* you have installed it. Sometimes they will be too old and sometimes too new for the Drupal codebase in question. This makes using them as standalone a completely unpredictable mess.

That’s also why Drush 12 has been officially announced as the first version which can’t be used as standalone at all — no matter how hard you would try. We still try, though, because we already have a good track record of making the impossible possible, like hosting Drupal 10 on Drush 8 based Aegir. Watch this space.
