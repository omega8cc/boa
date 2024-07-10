
# How To Migrate Single Sites Between Remote Ægir Instances

This is a detailed how-to for the `remote_import` Provision extension and `hosting_remote_import` module included by default in every Ægir Satellite Instance since BOA-2.0.3 Edition.

We assume that your Octopus system user is the default `o1`.

**Important**: The system user must be the same on source and target, since Ægir doesn't allow (yet) to migrate from `o1` to `o2`, only from `o1` to `o1` or from `o2` to `o2`, etc.

- The `source-host` is a placeholder for your source instance FQDN hostname.
- The `target-host` is a placeholder for your target instance FQDN hostname.
- The `plform-name` is a placeholder for the name of the imported codebase root directory.

## Caveats

1. The `ajax_comments` contrib module must be disabled and removed before site migration.
2. The Verify task on the migrated site must run without errors before migration.

You need to run the required commands and perform tasks in the order listed below:

## Commands to Run on Both Source and Target Server

```sh
touch /data/disk/o1/static/control/MyClassic.info
chsh -s /bin/bash o1
sed -i "s/^max_execution_time =.*/max_execution_time = 7200/g" /opt/php*/lib/php.ini
sed -i "s/^max_input_time =.*/max_input_time = 7200/g" /opt/php*/lib/php.ini
```

## Commands to Run on the Source Server Only

```sh
su - o1
nano ~/.ssh/authorized_keys ### Paste ~/.ssh/id_rsa.pub from the same account on target
chmod 600 ~/.ssh/*
```

## Commands to Run on the Target Server Only

```sh
su - o1
ssh-keyscan -t rsa -H source-host >> ~/.ssh/known_hosts
drush @hostmaster en hosting_remote_import -y
rsync -avzuL --exclude=plform-name/sites --ignore-errors -e ssh o1@source-host:/path/to/plform-name ~/static/
mkdir -p ~/static/plform-name/sites
rsync -avzuL --ignore-errors -e ssh o1@source-host:/path/to/plform-name/sites/all ~/static/plform-name/sites/
rsync -avzuL --ignore-errors -e ssh o1@source-host:/path/to/plform-name/sites/default ~/static/plform-name/sites/
```

Add the transferred platform codebase in the Ægir frontend with path: `/data/disk/o1/static/plform-name`

## Commands to Run on the Source Server Only

```sh
mv -f /var/xdrago/manage_ltd_users.sh /var/backups/
service clean-boa-env start
```

## Tasks to Perform on the Target Server Only

**Note**: You will have to wait for cron to run after every step or run the tasks cron manually with `bash /var/xdrago/run-o1`.

1. Go to `/node/add/server` in the Ægir control panel on the target instance.
2. Enter FQDN of the source server as a 'Server hostname'.
3. Choose only 'hostmaster' option under 'Remote Import' and hit 'Save'.
4. Go to 'Import remote sites' tab on the just added server node once verified.
5. Click on the "Retrieve a list..." button and run cron.
6. Choose the site to import from the list and hit 'Next'.
7. Choose the platform the site should be hosted on, hit 'Import' and run cron.
8. Wait... wait... wait... until it is done and the site is imported and verified.

Repeat steps 4-8 to migrate the next/more site(s).

## Commands to Run on the Source Server Only

```sh
mv -f /var/backups/manage_ltd_users.sh /var/xdrago/
```

## Commands to Run on Both Source and Target Server

```sh
chsh -s /bin/false o1
```
