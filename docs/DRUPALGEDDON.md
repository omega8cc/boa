# Drupalgeddon Daily Checks on D7 Sites

> **DEPRECATED (removed after 5.10.3).** The automated daily Drupalgeddon
> (SA-CORE-2014-005) hacked-site check described below no longer exists. It is
> no longer invoked by the nightly run, and the BOA upgrade path now deletes
> both control files fleet-wide: `/root/.force.drupalgeddon.cnf` and every
> `~/static/control/drupalgeddon.info`. Creating either file has no effect. The
> `drupalgeddon` Drush extension is still cloned and symlinked into `ltd` user
> homes (`~/.drush/usr/drupalgeddon`) for **manual** use only. The rest of this
> page is retained for historical reference and describes behaviour that is no
> longer active.

## ~/static/control/drupalgeddon.info

Previously enabled by default, now requires this control file to still run daily, because it may generate some false positives not always possible to avoid or silence, so it no longer makes sense to run this check daily, especially after BOA has run it automatically for a month and finally even disabled automatically all clearly compromised sites.

Note that your system administrator may still enable this with the root level control file `/root/.force.drupalgeddon.cnf`, so it will still run, even if you do not create the Octopus instance level empty control file:
`~/static/control/drupalgeddon.info`

Please note that the current version of the Drupalgeddon Drush extension needs the 'update' module to be enabled to avoid even more false positives, so BOA will enable the 'update' module temporarily while running this check, which in turn will result in even more email notices sent to the site admin email, if these notices are enabled.
