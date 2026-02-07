# How we build newer codebases for testing

## Prepare environment

```sh
  su -s /bin/bash - o3x
  mkdir -p ~/static/november-26/
  cd ~/static/november-26/
```

## Visit for latest versions check

```sh
  https://www.drupal.org/project/commerce
  https://www.drupal.org/project/farm
  https://www.drupal.org/project/localgov
  https://www.drupal.org/project/openculturas
  https://www.drupal.org/project/sector
  https://www.drupal.org/project/thunder
  https://www.drupal.org/project/varbase
```

## Build them one by one and document results

```sh
farmos     # farmos-3.4.6-10.4.9
           # visit: https://github.com/farmOS/farmOS/releases
           # wget https://github.com/farmOS/farmOS/releases/download/3.4.6/farmOS-3.4.6.tar.gz
           # (10.4.9)
```

```sh
cms        # composer create-project drupal/cms drupal_cms_installer-1.2.8-11.2.8 --no-dev --no-interaction --no-scripts
           # cd ~/static/november-26/drupal_cms_installer-1.2.8-11.2.8
           # composer update --no-scripts
           # composer install --no-dev
           # (11.2.8)
```

```sh
culturas   # composer create-project --remove-vcs drupal/openculturas_project openculturas-2.5.4-10.5.6 --no-dev --no-interaction --no-scripts
           # cd ~/static/november-26/openculturas-2.5.4-10.5.6
           # (10.5.6)
```

```sh
commerce   # composer create-project -s dev centarro/commerce-kickstart-project commerce_kickstart-3.2.0-11.2.8 --no-dev --no-interaction --no-scripts
           # cd ~/static/november-26/commerce_kickstart-3.2.0-11.2.8
           # composer require centarro/certified-projects
           # composer install --no-dev
           # (11.2.8)
```

```sh
localgov   # composer create-project localgovdrupal/localgov-project:^3.0 localgov-3.3.1-10.5.6 --no-dev --no-interaction --no-scripts
           # cd ~/static/november-26/localgov-3.3.1-10.5.6
           # (10.5.6)
```

```sh
sector     # composer create-project drupal/sector_project_template:11.x-dev sector-11.0.x-dev-11.2.8 --no-dev --no-interaction --no-scripts
           # cd ~/static/november-26/sector-11.0.x-dev-11.2.8
           # composer update
           # composer install --no-dev
           # (11.2.8)
```

```sh
thunder    # composer create-project thunder/thunder-project thunder-8.2.6-11.2.8 --no-dev --no-interaction --no-install --no-scripts
           # cd /data/disk/o3x/static/november-26/thunder-8.2.6-11.2.8
           # composer config --no-plugins allow-plugins.drupal/core-composer-scaffold true
           # composer install --no-dev
           # (11.2.8)
```

```sh
varbase    # composer create-project Vardot/varbase-project:~10 varbase-10.0.8-10.5.6 --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/november-26/varbase-10.0.8-10.5.6
           # composer config --no-plugins allow-plugins.drupal/core-composer-scaffold true
           # composer install --no-dev
           # cd ~/static/november-26/varbase-10.0.8-10.5.6/docroot
           # find -name recipes | awk '{print $1"/default/content"}' | xargs -I {} mkdir -p {}
           # (10.5.6)
```

```sh
varbase    # composer create-project Vardot/varbase-project:~9 varbase-9.1.12-10.5.2 --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/november-26/varbase-9.1.12-10.5.2
           # composer config --no-plugins allow-plugins.drupal/core-composer-scaffold true
           # composer install --no-dev
           # cd ~/static/november-26/varbase-9.1.12-10.5.2/docroot
           # find -name recipes | awk '{print $1"/default/content"}' | xargs -I {} mkdir -p {}
           # (10.5.6)
```

```sh
vanilla    # composer create-project drupal/recommended-project:10.2.12 drupal-10.2.12 --no-dev --no-interaction
           # cd ~/static/november-26/drupal-10.2.12
           # composer require drush/drush
           # (10.2.12)
```

```sh
vanilla    # composer create-project drupal/recommended-project:10.3.14 drupal-10.3.14 --no-dev --no-interaction
           # cd ~/static/november-26/drupal-10.3.14
           # composer require drush/drush
           # (10.3.14)
```

```sh
vanilla    # composer create-project drupal/recommended-project:10.4.9 drupal-10.4.9 --no-dev --no-interaction
           # cd ~/static/november-26/drupal-10.4.9
           # composer require drush/drush
           # (10.4.9)
```

```sh
vanilla    # composer create-project drupal/recommended-project:10.5.6 drupal-10.5.6 --no-dev --no-interaction
           # cd ~/static/november-26/drupal-10.5.6
           # composer require drush/drush
           # (10.5.6)
```

```sh
vanilla    # composer create-project drupal/recommended-project:11.1.9 drupal-11.1.9 --no-dev --no-interaction
           # cd ~/static/november-26/drupal-11.1.9
           # composer require drush/drush
           # (11.1.9)
```

```sh
vanilla    # composer create-project drupal/recommended-project:11.2.8 drupal-11.2.8 --no-dev --no-interaction
           # cd ~/static/november-26/drupal-11.2.8
           # composer require drush/drush
           # (11.2.8)
```

## Check and compare versions built above

```sh
o3x@modern:~/static/november-26$ ls -la
drwxr-sr-x 12 o3x users 4096 Nov 26 22:00 commerce_kickstart-3.2.0-11.2.8
drwxr-sr-x  4 o3x users 4096 Nov 28 13:42 drupal-10.2.12
drwxr-sr-x  4 o3x users 4096 Nov 28 13:43 drupal-10.3.14
drwxr-sr-x  4 o3x users 4096 Nov 28 13:44 drupal-10.4.9
drwxr-sr-x  4 o3x users 4096 Nov 28 13:45 drupal-10.5.6
drwxr-sr-x  5 o3x users 4096 Nov 28 13:46 drupal-11.1.9
drwxr-sr-x  5 o3x users 4096 Nov 28 13:46 drupal-11.2.8
drwxr-sr-x  6 o3x users 4096 Nov 27 13:36 drupal_cms_installer-1.2.8-11.2.8
drwxr-xr-x  6 o3x users 4096 Nov 27 00:28 farmos-3.4.6-10.4.9
drwxr-sr-x 11 o3x users 4096 Nov 26 22:03 localgov-3.3.1-10.5.6
drwxr-sr-x  8 o3x users 4096 Nov 27 00:38 openculturas-2.5.4-10.5.6
drwxr-sr-x  6 o3x users 4096 Nov 26 22:05 sector-11.0.x-dev-11.2.8
drwxr-sr-x  6 o3x users 4096 Nov 26 22:07 thunder-8.2.6-11.2.8
drwxr-sr-x 11 o3x users 4096 Nov 26 22:17 varbase-10.0.8-10.5.6
drwxr-sr-x  7 o3x users 4096 Nov 26 22:20 varbase-9.1.12-10.5.2
o3x@modern:~/static/november-26$
```

## Add them all as platforms in Ægir

Use paths like `november-26/thunder-8.2.6-11.2.8` and run tests for sites install, clone and migration.

## Notes on non-standard issues

Some codebases need manual fixes after the build. For example `openculturas` has wrong installation profile directory tree structure by default and doesn't have required `sites/example.sites.php` file, which needs to be copied there manually before you can install sites.


