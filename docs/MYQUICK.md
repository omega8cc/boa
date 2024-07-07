# Super Fast Site Cloning and Migration

It is now possible to enable blazing fast migrations and cloning, even for sites with complex and large databases, using this control file:

`~/static/control/MyQuick.info`

## How Fast is Super-Fast?

It's faster than you would expect! We have observed it speeding up clone and migration tasks that normally take 1-2 hours to just 3-6 minutes. Yes, that's how fast it is!

This file, if it exists, will enable a super fast per-table and parallel database dump and import. However, it will not leave a conventional complete database dump file in the site archive normally created by Aegir when you run not only the backup task, but also clone, migrate, and delete tasks. Consequently, the restore task will not work anymore.

We need to emphasize this again: with this control file present, all normally slow tasks will become blazing fast, but at the cost of not keeping an archived complete database dump file in the site directory archive where it would otherwise be included.

## Important Considerations

Of course, the system still maintains nightly backups of all your sites using the new split SQL dump archives. However, with this control file present, you won't be able to use the restore task in Aegir because the site archive won't include the database dump. You can still find that SQL dump split into per-table files in the backups directory, though, in a subdirectory with a timestamp added, so you can still access it manually if needed.

For more information, please visit the [documentation](https://github.com/omega8cc/boa/tree/5.x-dev/docs).

