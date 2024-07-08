
# Please check regularly: [PHP Supported Versions](https://www.php.net/supported-versions.php)

The Aegir version provided by BOA is now fully compatible with PHP 8.3, so it can be used as default version in the Aegir PHP configuration files:
`~/static/control/cli.info` and `~/static/control/fpm.info`

## PHP CAVEATS for Drupal core 7-10 versions:

- [Drupal 7 PHP Requirements](https://www.drupal.org/docs/7/system-requirements/php-requirements)
- [Drupal System Requirements](https://www.drupal.org/docs/system-requirements/php-requirements)

# Support for PHP-FPM Version Switch per Octopus Instance (also per site)

`~/static/control/fpm.info`

This file, if it exists and contains a supported and installed PHP-FPM version, will be used by a system agent running every 2-3 minutes to switch the PHP-FPM version used for serving web requests by this Octopus instance.

**IMPORTANT**: If used, it will switch PHP-FPM for all Drupal sites hosted on the instance, unless a `multi-fpm.info` control file also exists.

## Supported Values for Single PHP-FPM Mode:

- 8.3
- 8.2
- 8.1
- 8.0
- 7.4
- 7.3
- 7.2
- 7.1
- 7.0
- 5.6

**NOTE**: There must be only one line and one value (e.g., `8.1`) in this file. Otherwise, it will be ignored.

**NOTE**: If the file doesn't exist, the system will create it and set it to the lowest available PHP version installed, not the system default version. This is to guarantee backward compatibility for instances installed before upgrading to BOA-4.1.3 when the default PHP version was 5.6. Otherwise, after the upgrade, the system would automatically switch such accounts to the new default PHP version, which is 8.1, and this could break most of the sites hosted, never before tested for PHP 8.1 compatibility.

# Multi-PHP-FPM Support for Sites on Octopus Instance

It is now possible to make all installed PHP-FPM versions available simultaneously for sites on the Octopus instance with an additional control file:

`~/static/control/multi-fpm.info`

This file, if it exists, will switch all sites listed in it to their respective PHP-FPM versions as shown in the example below, while all other sites not listed in `multi-fpm.info` will continue to use the PHP-FPM version defined in `fpm.info` instead, which can be modified independently.

```
foo.com 8.1
bar.com 7.4
old.com 5.6
```

**NOTE**: Each line in the `multi-fpm.info` file must start with the main site name (not an alias), followed by a single space, and then the PHP-FPM version to use.

# Support for PHP-CLI Version Switch per Octopus Instance (all sites)

`~/static/control/cli.info`

This file, similar to `fpm.info`, if it exists and contains a supported and installed PHP version, will be used by a system agent running every 2-3 minutes to switch the PHP-CLI version for this Octopus instance, but it will do this for all hosted sites. There is no option to switch or override this per site hosted (yet).

## Supported Values:

- 8.3
- 8.2
- 8.1
- 8.0
- 7.4
- 7.3
- 7.2
- 7.1
- 7.0
- 5.6

There must be only one line and one value (e.g., `8.1`) in this control file. Otherwise, it will be ignored.

**NOTE**: If the file doesn't exist, the system will create it and set it to the lowest available PHP version installed, not the system default version. This is to guarantee backward compatibility for instances installed before upgrading to BOA-4.1.3 when the default PHP version was 5.6. Otherwise, after the upgrade, the system would automatically switch such accounts to the new default PHP version, which is 8.1, and this could break most of the sites hosted, never before tested for PHP 8.1 compatibility.

**IMPORTANT**: This file will affect Drush on the shell user command line, Drush in the Aegir backend, and also the PHP-CLI version used by Composer on the command line.
