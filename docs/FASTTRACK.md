# Even Faster Site Cloning and Migration

It is now possible to speed up the already blazing fast migrations and cloning with this empty control file:

`~/static/control/FastTrack.info`

This file, if it exists, will drastically reduce the number of tasks otherwise launched automatically in preparation for clone and migrate, namely:

1. Both source and target platforms will no longer be verified.
2. The site will no longer be verified before running clone or migrate.

Please carefully consider the implications, though, because there are very good reasons for these extra tasks to be launched before running clone or migrate to make sure that any issues are detected and fixed for you early and not during migration or clone, which could otherwise break the site and leave it in a state not easy to fix, especially without root access to the system.

The potential reasons to disable these extra tasks with the help of this new control file can be twofold:

1. To restore default and much faster Aegir own behaviour.
2. To help those running mass migrations to avoid running duplicate tasks.

Still, it's your responsibility to run these extra verify tasks when you need to migrate or clone just a single site, but you prefer to have them run for you automatically as before, you can easily restore the previous behaviour:

1. Create empty `~/static/control/ClassicTrack.info`.
2. Delete `~/static/control/FastTrack.info`.
