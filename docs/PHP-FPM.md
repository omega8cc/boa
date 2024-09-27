# PHP-FPM Version Management in BOA

The Ægir version provided by BOA is now fully compatible with PHP 8.3, so it can be used as default version in the Ægir PHP configuration files:
`~/static/control/cli.info` and `~/static/control/fpm.info`

### Global PHP-FPM Version Control

BOA allows you to manage the PHP-FPM version across all sites hosted on an Octopus instance using the `fpm.info` file.

- The `~/static/control/fpm.info` file, if it exists and contains a supported and installed PHP-FPM version, will be used by a system agent running every 2-3 minutes to switch the PHP-FPM version used for all web requests on this Octopus instance.

#### **IMPORTANT**:
- If used, this will switch PHP-FPM for **all** Drupal sites hosted on the instance, unless a `multi-fpm.info` control file also exists.

### Supported Values for Single PHP-FPM Mode:
- 8.3, 8.2, 8.1, 8.0, 7.4, 7.3, 7.2, 7.1, 7.0, 5.6

#### **NOTE**:
- Only one line and one value (e.g., `8.1`) should be present in this file; otherwise, the system will ignore it.
- If the `fpm.info` file doesn’t exist, the system will create it and set it to the lowest available PHP version installed, not the system default version. This ensures backward compatibility for instances installed before upgrading to BOA-4.1.3 when the default PHP version was 5.6. Without this safeguard, upgrading could break most hosted sites that haven't been tested for PHP 8.1 compatibility.

---

### Multi-PHP-FPM Support for Sites on Octopus Instance

You can enable multiple PHP versions for different sites using the `multi-fpm.info` file.

- **File Location**: `~/static/control/multi-fpm.info`
- If this file exists, it will override the default `fpm.info` configuration for the sites listed in the `multi-fpm.info` file.

Example of `multi-fpm.info`:
```
foo.com 8.1
bar.com 7.4
old.com 5.6
```

- **NOTE**: Each line in the `multi-fpm.info` file must start with the **main site name** (not an alias), followed by a single space, and then the PHP-FPM version to use.

#### **IMPORTANT**: Supported Drupal core versions and distributions have different PHP versions requirements, while not all PHP versions out of currently supported ten versions are installed by default. Ensure that you have corresponding PHP versions installed with barracuda before attempting to install older Drupal versions and distributions. On hosted BOA contact your host if you need any legacy PHP installed again.

#### PHP CAVEATS for Drupal core 7-10 versions:

- [Drupal 7 PHP Requirements](https://www.drupal.org/docs/7/system-requirements/php-requirements)
- [Drupal System Requirements](https://www.drupal.org/docs/system-requirements/php-requirements)

#### Please check regularly: [PHP Supported Versions](https://www.php.net/supported-versions.php)
