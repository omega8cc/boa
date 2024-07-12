# Drupalgeddon Daily Checks on D7 Sites

## ~/static/control/drupalgeddon.info

Previously enabled by default, now requires this control file to still run daily, because it may generate some false positives not always possible to avoid or silence, so it no longer makes sense to run this check daily, especially after BOA has run it automatically for a month and finally even disabled automatically all clearly compromised sites.

Note that your system administrator may still enable this with the root level control file `/root/.force.drupalgeddon.cnf`, so it will still run, even if you do not create the Octopus instance level empty control file:
`~/static/control/drupalgeddon.info`

Please note that the current version of the Drupalgeddon Drush extension needs the 'update' module to be enabled to avoid even more false positives, so BOA will enable the 'update' module temporarily while running this check, which in turn will result in even more email notices sent to the site admin email, if these notices are enabled.
