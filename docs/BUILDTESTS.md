# How we build newer codebases for testing

## Prepare environment

```sh
  su -s /bin/bash - o3x
  mkdir -p ~/static/february-6/
  cd ~/static/february-6/
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
farmos     # farm-3.5.1-10.6.3
           # visit: https://github.com/farmOS/farmOS/releases
           # wget https://github.com/farmOS/farmOS/releases/download/3.5.1/farmOS-3.5.1.tar.gz
           # tar -xzf farmOS-3.5.1.tar.gz
           # mv farmOS farm-3.5.1-10.6.3
           # (10.6.3)
```

```sh
cms        # composer create-project drupal/cms drupal_cms_installer-2.0.0-11.3.3 --no-dev --no-interaction --no-scripts
           # cd ~/static/february-6/drupal_cms_installer-2.0.0-11.3.3
           # composer update --no-scripts
           # composer install --no-dev
           # (11.3.3)
```

```sh
culturas   # composer create-project --remove-vcs drupal/openculturas_project openculturas-2.5.4-10.5.8 --no-dev --no-interaction --no-scripts
           # cd ~/static/february-6/openculturas-2.5.4-10.5.8/web/profiles/contrib/openculturas-distribution
           # mv profile openculturas
           # mv openculturas ~/static/february-6/openculturas-2.5.4-10.5.8/web/profiles/contrib/
           # mv * ~/static/february-6/openculturas-2.5.4-10.5.8/web/profiles/contrib/
           # cd ~/static/february-6/openculturas-2.5.4-10.5.8/web/profiles/contrib/
           # rm -rf openculturas-distribution
           # cp ~/static/february-6/farm-3.5.1-10.6.3/web/sites/example.sites.php ~/static/february-6/openculturas-2.5.4-10.5.8/web/sites/
           # (10.5.8)
```

```sh
commerce   # composer create-project -s dev centarro/commerce-kickstart-project commerce_kickstart-3.2.0-11.3.3 --no-dev --no-interaction --no-scripts
           # cd ~/static/february-6/commerce_kickstart-3.2.0-11.3.3
           # composer require centarro/certified-projects
           # composer install --no-dev
           # (11.3.3)
```

```sh
localgov   # composer create-project localgovdrupal/localgov-project localgov-3.4.0-10.6.3 --no-dev --no-interaction --no-scripts
           # cd ~/static/february-6/localgov-3.4.0-10.6.3
           # (10.6.3)
```

```sh
sector     # composer create-project drupal/sector_project_template:11.x-dev sector-11.0.x-dev-11.3.3 --no-dev --no-interaction --no-scripts
           # cd ~/static/february-6/sector-11.0.x-dev-11.3.3
           # composer update
           # composer install --no-dev
           # (11.3.3)
```

```sh
thunder    # composer create-project thunder/thunder-project thunder-8.3.1-11.3.3 --no-dev --no-interaction --no-install --no-scripts
           # cd /data/disk/o3x/static/february-6/thunder-8.3.1-11.3.3
           # composer config --no-plugins allow-plugins.drupal/core-composer-scaffold true
           # composer install --no-dev
           # (11.3.3)
```

```sh
varbase    # composer create-project Vardot/varbase-project:~10 varbase-10.1.0-11.3.1 --no-dev --no-interaction --no-install --no-scripts
           # ln -sf /opt/php84/bin/php /usr/bin/php
           # cd ~/static/february-6/varbase-10.1.0-11.3.1
           # composer config --no-plugins allow-plugins.drupal/core-composer-scaffold true
           # composer install --no-dev
           # cd ~/static/february-6/varbase-10.1.0-11.3.1/docroot
           # find -name recipes | awk '{print $1"/default/content"}' | xargs -I {} mkdir -p {}
           # (11.3.1)
```

```sh
varbase    # composer create-project Vardot/varbase-project:~9 varbase-9.1.13-10.6.1 --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/february-6/varbase-9.1.13-10.6.1
           # composer config --no-plugins allow-plugins.drupal/core-composer-scaffold true
           # composer install --no-dev
           # cd ~/static/february-6/varbase-9.1.13-10.6.1/docroot
           # find -name recipes | awk '{print $1"/default/content"}' | xargs -I {} mkdir -p {}
           # (10.6.1)
```

```sh
vanilla    # composer create-project drupal/recommended-project:10.2.12 drupal-10.2.12 --no-dev --no-interaction
           # cd ~/static/february-6/drupal-10.2.12
           # composer require drush/drush
           # composer audit
           # (10.2.12)
```

```sh
vanilla    # composer create-project drupal/recommended-project:10.3.14 drupal-10.3.14 --no-dev --no-interaction
           # cd ~/static/february-6/drupal-10.3.14
           # composer require drush/drush
           # composer audit
           # (10.3.14)
```

```sh
vanilla    # composer create-project drupal/recommended-project:10.4.9 drupal-10.4.9 --no-dev --no-interaction
           # cd ~/static/february-6/drupal-10.4.9
           # composer require drush/drush
           # composer audit
           # (10.4.9)
```

```sh
vanilla    # composer create-project drupal/recommended-project:10.5.8 drupal-10.5.8 --no-dev --no-interaction
           # cd ~/static/february-6/drupal-10.5.8
           # composer require drush/drush
           # composer audit
```

```sh
vanilla    # composer create-project drupal/recommended-project:10.6.3 drupal-10.6.3 --no-dev --no-interaction
           # cd ~/static/february-6/drupal-10.6.3
           # composer require drush/drush
           # composer audit
           # (10.6.3)
```

```sh
vanilla    # composer create-project drupal/recommended-project:11.1.9 drupal-11.1.9 --no-dev --no-interaction
           # cd ~/static/february-6/drupal-11.1.9
           # composer require drush/drush
           # composer audit
           # (11.1.9)
```

```sh
vanilla    # composer create-project drupal/recommended-project:11.2.10 drupal-11.2.10 --no-dev --no-interaction
           # cd ~/static/february-6/drupal-11.2.10
           # composer require drush/drush
           # composer audit
           # (11.2.10)
```

```sh
vanilla    # composer create-project drupal/recommended-project:11.3.3 drupal-11.3.3 --no-dev --no-interaction
           # cd ~/static/february-6/drupal-11.3.3
           # composer require drush/drush
           # composer audit
           # (11.3.3)
```


## Check and compare versions built above

```sh
o3x@modern:~/static/february-6$ ls -la
-rw-r--r-- 1 o3x users 68M Feb  7 20:19 commerce_kickstart-3.2.0-11.3.3.tar.gz
-rw-r--r-- 1 o3x users 20M Feb  7 20:12 drupal-10.2.12.tar.gz
-rw-r--r-- 1 o3x users 22M Feb  7 20:12 drupal-10.3.14.tar.gz
-rw-r--r-- 1 o3x users 23M Feb  7 20:11 drupal-10.4.9.tar.gz
-rw-r--r-- 1 o3x users 23M Feb  7 20:11 drupal-10.5.8.tar.gz
-rw-r--r-- 1 o3x users 23M Feb  7 20:11 drupal-10.6.3.tar.gz
-rw-r--r-- 1 o3x users 21M Feb  7 20:10 drupal-11.1.9.tar.gz
-rw-r--r-- 1 o3x users 22M Feb  7 20:10 drupal-11.2.10.tar.gz
-rw-r--r-- 1 o3x users 22M Feb  7 20:09 drupal-11.3.3.tar.gz
-rw-r--r-- 1 o3x users 89M Feb  7 20:15 drupal_cms_installer-2.0.0-11.3.3.tar.gz
-rw-r--r-- 1 o3x users 25M Feb  7 20:14 farm-3.5.1-10.6.2.tar.gz
-rw-r--r-- 1 o3x users 83M Feb  7 20:18 localgov-3.4.0-10.6.3.tar.gz
-rw-r--r-- 1 o3x users 71M Feb  7 20:17 openculturas-2.5.4-10.5.8.tar.gz
-rw-r--r-- 1 o3x users 34M Feb  7 20:17 sector-11.0.x-dev-11.3.3.tar.gz
-rw-r--r-- 1 o3x users 34M Feb  7 20:16 thunder-8.3.1-11.3.3.tar.gz
-rw-r--r-- 1 o3x users 97M Feb  7 20:13 varbase-10.1.0-11.3.1.tar.gz
-rw-r--r-- 1 o3x users 53M Feb  7 20:16 varbase-9.1.13-10.6.1.tar.gz
o3x@modern:~/static/february-6$
```

## Add them all as platforms in Ægir

Use paths like `february-6/drupal-11.3.3` and run tests for sites install, clone and migration.

## Notes on non-standard issues

Some codebases need manual fixes after the build. For example `openculturas` has wrong installation profile directory tree structure by default and doesn't have required `sites/example.sites.php` file, which needs to be copied there manually before you can install sites.


