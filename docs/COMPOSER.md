
# Composer on BOA: Common Questions and Answers

Here are responses to some common Composer on BOA related questions.

The only documentation source for anything Ægir on BOA related is available at:
- [Omega8.cc Documentation](https://learn.omega8.cc)
- [BOA GitHub Issues](https://github.com/omega8cc/boa/issues?utf8=✓&q=is%3Aissue+composer)

**IMPORTANT:** You must switch your `~/static/control/cli.info` to PHP version 8.1 or newer (BOA hosted on Omega8.cc comes with 8.3, 8.2, 8.1, etc.), because D10 based distros require at least PHP 8.1. This also means that to run the sites installed after switching `cli.info` to 8.1 or newer, you will also need to either switch your `~/static/control/fpm.info` to 8.1 or newer, or more probably, to not break any existing sites not compatible with PHP 8.1+, you will need to list these old sites names in `~/static/control/multi-fpm.info`.

For more information, please check:
- [How To Quickly Switch PHP to Newer Version](https://learn.omega8.cc/how-to-quickly-switch-php-to-newer-version-330)

BOA supports Drupal 8/9/10 codebases both with classic directory structure like in Drupal 7 and also Drupal 8/9/10 distros you can download from Drupal.org. However, if you use a Composer-based codebase with a different structure, the platform path is not the codebase root directory but the subdirectory where you see the Drupal own `index.php` and `core` subdirectory. It can be `platform-name/web` or `platform-name/docroot` or something similar depending on the distro design.

As you may have discovered if you have already tried, the path you should use in Ægir when adding a Composer-based codebase as a platform is the directory where `index.php` resides, so effectively anything above that directory is not available for web requests and thus safely protected.

The information from Ægir project docs saying "When verifying a platform, Ægir runs `composer install` if a `composer.json` file is found." doesn't apply to BOA. We have disabled this. There are several reasons, most importantly:

a. Having this feature enabled is actually against the codebase management workflow in Ægir, because it may modify codebase on a live site.
b. Some tasks launch verify many times during clone and migrate, which results in giant overhead and conflicts if we allowed it to run `composer install` many times in parallel.
c. From our experience, having this poorly implemented feature enabled breaks clone and migration tasks between platforms when both have the `composer.json` file. It just doesn't make any sense in our opinion. The implementation should be improved to make it actually work similarly to Drush Makefiles.

You should think about Composer like it was Drush Make replacement, and you should not re-build nor upgrade the codebase on a platform with sites already hosted. Just use it to build new codebases and then add them as platforms when the build works without errors.

You can modify the default path to configuration files in the site's `local.settings.php` file. We are looking into making it easier to configure, preferably with site-level INI files which are easier to edit safely. Just define your custom path in `local.settings.php` overriding the default:

```php
$config_directories[CONFIG_SYNC_DIRECTORY] = 'sites/sitename/private/config/sync';
```

Please also check the official docs at:
- [Changing the Storage Location of the Sync Directory](https://www.drupal.org/docs/8/configuration-management/changing-the-storage-location-of-the-sync-directory)

Please submit questions, suggestions, and patches to improve the docs in our issue queue at:
- [BOA GitHub Issues](https://github.com/omega8cc/boa/issues)
