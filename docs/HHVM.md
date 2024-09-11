# What is HHVM? (deprecated)

HHVM is an open-source virtual machine designed for executing programs written in Hack and PHP. HHVM uses a just-in-time (JIT) compilation approach to achieve superior performance while maintaining the development flexibility that PHP provides.

Please visit [HHVM.com](http://hhvm.com) for more information on the project.

If you are interested in some real-world benchmarks, please check also:

- [WP Engine Benchmark](http://wpengine.com/2014/11/19/hhvm-project-mercury/)
- [Wikimedia Benchmark](http://blog.wikimedia.org/2014/12/29/how-we-made-editing-wikipedia-twice-as-fast/)

# How to Install HHVM on BOA System

On self-hosted BOA, you must add the 'HVM' symbol to the `_XTRAS_LIST` variable in your `/root/.barracuda.cnf` file and then run the `barracuda up-lts` command, followed by `octopus up-lts all aegir`, before trying to enable HHVM on any existing Octopus Satellite Instance.

Once BOA-2.4.0 is released, HHVM can be installed also with standard commands recommended for production systems: `barracuda up-lts` for Ægir Master, followed by `octopus up-lts all aegir` for Satellite Instances.

Please note that it is not enough to run `barracuda up-lts system`, because you need to upgrade the system plus Ægir Master and all Satellite Instances.

This step will be automated on BOA managed by Omega8.cc, and we plan to make HHVM available on the high-end Power Engines: [Omega8.cc Power Engines](https://omega8.cc/power)

# How to Use HHVM on BOA System, Side by Side with PHP-FPM

To enable HHVM on any Octopus Satellite Instance, follow these steps:

1. Create an empty control file: `touch ~/static/control/hhvm.info`
2. Wait 1-2 minutes
3. Done! This particular Octopus instance is now powered by HHVM

To disable HHVM on the Octopus Satellite Instance, follow these steps:

1. Delete existing `~/static/control/hhvm.info` control file
2. Create non-empty control file: `echo 7.2 > ~/static/control/fpm.info`
3. Wait 2-3 minutes
4. Done! This particular Octopus instance is now powered by PHP-FPM

As you can see, it is possible to run multiple Octopus Satellite Instances, some powered by HHVM, while others by PHP-FPM, on the same BOA system.

# Caveats and Some Good-to-Know Details

- BOA supports HHVM only on Debian Jessie/Stretch.

- There is no `phpinfo()` available, but you can emulate it with a bundled file: [hhvminfo.php](https://github.com/omega8cc/boa/blob/master/aegir/conf/hhvm/view/hhvminfo.php). Upload it to any existing Drupal site platform root directory and rename to whitelisted `rtoc.php` filename. Then just visit `http://foo.com/rtoc.php`.

- HHVM doesn't support `disable_functions` PHP INI directive, so we emulate it to match BOA-specific PHP-FPM behaviour using the trick mentioned at: [GitHub Issue 2745](https://github.com/facebook/hhvm/issues/2745#issuecomment-47134544).

- BOA doesn't monitor HHVM (yet), so while it will be started automatically on system boot, it will not be (re)started if it crashes for some reason. It is a work in progress.

- Currently, the Octopus Satellite Instance upgrade will automatically switch the instance back to the available PHP-FPM version, so the control file doesn't make HHVM permanent per instance (yet). If you happen to upgrade Octopus while it runs on HHVM, you will have to replace `~/static/control/hhvm.info` with `~/static/control/fpm.info` after the upgrade, wait a few minutes and then create the `~/static/control/hhvm.info` control file again.

- In contrast to PHP-FPM mode, which runs as your SSH/FTPS user, HHVM runs as a special, very limited system user created or destroyed on the fly per Octopus instance when you enable or disable HHVM on the given instance. This helps to mirror security restrictions available in the PHP-FPM mode.

# FAQ

**Q: Is it possible to have HHVM as an option, just like other versions of PHP, e.g., 5.4, 5.5 and HHVM so it can be chosen on a per site / platform basis?**

**A:** It is an option, but not exactly like other PHP-related options, because you can't control HHVM version. It also requires Nginx config modification on the fly. It also requires a custom system user created on the fly.

This must be done on the Octopus Satellite Instance configuration level, and can't be done on the Ægir platform nor Drupal site level.

We also want to make it possible to switch Octopus Satellite Instance between PHP-FPM and HHVM without system root privileges, so it can't depend on some variable in the Octopus Satellite Instance .cnf file.

Note also that currently it is not possible to define HHVM as a default engine during Octopus instance install or upgrade.

Also, you still need a standard PHP installed anyway, so it can be used by the Ægir/Drush backend, and that is why you can't specify HHVM as an option *instead* of PHP version.

**Q: Is it possible to initiate HHVM restart without root access?**

**A:** Not yet, but we are working on it.
