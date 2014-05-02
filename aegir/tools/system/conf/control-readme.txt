#-### Support for PHP FPM/CLI version safe switch per Octopus instance

  This allows to easily switch PHP version by the instance owner w/o system
  admin (root) help. All you need to do is to create ~/static/control/fpm.info
  and ~/static/control/cli.info file with a single line telling the system
  which available PHP version should be used (if installed): 5.5 or 5.4 or 5.3

  Only one of them can be set, but you can use separate versions for web access
  (fpm.info) and the Aegir backend (cli.info). The system will switch versions
  defined via these control files in 5 minutes or less. We use external control
  files and not any option in the Aegir interface to make sure you will never
  lock yourself by switching to version which may cause unexpected problems.

  Note that the same version will be used in all platforms and all sites hosted
  on the same Octopus instance. Why not to try latest and greatest PHP 5.5 now?

