# How we build newer codebases for testing

## Prepare environment

```sh
  su -s /bin/bash - o3x
  mkdir -p ~/static/june-8/
  cd ~/static/june-8/
  composer clearcache
```

## Visit for latest versions check

```sh
  https://www.drupal.org/project/cms
  https://www.drupal.org/project/commerce
  https://www.drupal.org/project/farm
  https://www.drupal.org/project/localgov
  https://www.drupal.org/project/openculturas
  https://www.drupal.org/project/thunder
  https://www.drupal.org/project/varbase
```

## Build them one by one and document results

```sh
farmos     # farm-4.0.2-11.3.11
           # visit: https://github.com/farmOS/farmOS/releases
           # wget https://github.com/farmOS/farmOS/releases/download/4.0.2/farmOS-4.0.2.tar.gz
           # tar -xzf farmOS-4.0.2.tar.gz
           # mv farmOS farm-4.0.2-11.3.11
           # cd ~/static/june-8/farm-4.0.2-11.3.11
           # composer update --no-scripts
           # composer install --no-dev
           # (11.3.11)
```

```sh
cms        # composer create-project drupal/cms drupal_cms_installer-2.1.3-11.3.11 --no-dev --no-interaction --no-scripts
           # cd ~/static/june-8/drupal_cms_installer-2.1.3-11.3.11
           # composer update --no-scripts
           # composer install --no-dev
           # composer require drush/drush
           # (11.3.11)
```

```sh
culturas   # composer create-project --remove-vcs drupal/openculturas_project openculturas-3.0.1-11.3.11 --no-dev --no-interaction --no-scripts
           # cd ~/static/june-8/openculturas-3.0.1-11.3.11/
           # composer update --no-scripts
           # composer install --no-dev
           # cd ~/static/june-8/openculturas-3.0.1-11.3.11/web/profiles/contrib/openculturas-distribution
           # mv profile openculturas
           # mv openculturas ~/static/june-8/openculturas-3.0.1-11.3.11/web/profiles/contrib/
           # mv * ~/static/june-8/openculturas-3.0.1-11.3.11/web/profiles/contrib/
           # cd ~/static/june-8/openculturas-3.0.1-11.3.11/web/profiles/contrib/
           # rm -rf openculturas-distribution
           # cp ~/static/june-8/farm-4.0.2-11.3.11/web/sites/example.sites.php ~/static/june-8/openculturas-3.0.1-11.3.11/web/sites/
           # (11.3.11)
```

```sh

commerce   # composer create-project -s dev centarro/commerce-kickstart-project commerce_kickstart-3.3.6-11.3.11 --no-dev --no-interaction --no-scripts
           # cd ~/static/june-8/commerce_kickstart-3.3.6-11.3.11
           # composer require centarro/certified-projects
           # composer update --no-scripts
           # composer install --no-dev
           # (11.3.11)
```

```sh
localgov   # composer create-project drupal/localgov_project:^4.0 localgov-4.0.3-11.3.11 --no-dev --no-interaction --no-scripts
           # cd ~/static/june-8/localgov-4.0.3-11.3.11
           # composer update --no-scripts
           # composer install --no-dev
           # (11.3.11)
```

```sh
thunder    # composer create-project thunder/thunder-project thunder-8.3.6-11.3.11 --no-dev --no-interaction --no-install --no-scripts
           # cd /data/disk/o3x/static/june-8/thunder-8.3.6-11.3.11
           # composer config --no-plugins allow-plugins.drupal/core-composer-scaffold true
           # composer update --no-scripts
           # composer install --no-dev
           # (11.3.11)
```

```sh
varbase    # composer create-project Vardot/varbase-project:~10 varbase-10.1.0-11.3.11 --no-dev --no-interaction --no-install --no-scripts
           # ln -sf /opt/php84/bin/php /usr/bin/php
           # cd ~/static/june-8/varbase-10.1.0-11.3.11
           # composer config --no-plugins allow-plugins.drupal/core-composer-scaffold true
           # composer update --no-scripts
           # composer install --no-dev
           # cd ~/static/june-8/varbase-10.1.0-11.3.11/docroot
           # find -name recipes | awk '{print $1"/default/content"}' | xargs -I {} mkdir -p {}
           # (11.3.11)
```

```sh
vanilla    # composer create-project drupal/recommended-project:10.2.12 drupal-10.2.12 --no-dev --no-interaction
           # cd ~/static/june-8/drupal-10.2.12
           # composer require drush/drush
           # composer audit
           # (10.2.12)
```

```sh
vanilla    # composer create-project drupal/recommended-project:10.3.14 drupal-10.3.14 --no-dev --no-interaction
           # cd ~/static/june-8/drupal-10.3.14
           # composer require drush/drush
           # composer audit
           # (10.3.14)
```

```sh
vanilla    # composer create-project drupal/recommended-project:10.4.10 drupal-10.4.10 --no-dev --no-interaction
           # cd ~/static/june-8/drupal-10.4.10
           # composer require drush/drush
           # composer audit
           # (10.4.10)
```

```sh
vanilla    # composer create-project drupal/recommended-project:10.5.10 drupal-10.5.10 --no-dev --no-interaction
           # cd ~/static/june-8/drupal-10.5.10
           # composer require drush/drush
           # composer audit
           # (10.5.10)
```

```sh
vanilla    # composer create-project drupal/recommended-project:10.6.10 drupal-10.6.10 --no-dev --no-interaction
           # cd ~/static/june-8/drupal-10.6.10
           # composer require drush/drush
           # composer audit
           # (10.6.10)
```

```sh
vanilla    # composer create-project drupal/recommended-project:11.1.10 drupal-11.1.10 --no-dev --no-interaction
           # cd ~/static/june-8/drupal-11.1.10
           # composer require drush/drush
           # composer audit
           # (11.1.10)
```

```sh
vanilla    # composer create-project drupal/recommended-project:11.2.13 drupal-11.2.13 --no-dev --no-interaction
           # cd ~/static/june-8/drupal-11.2.13
           # composer require drush/drush
           # composer audit
           # (11.2.13)
```

```sh
vanilla    # composer create-project drupal/recommended-project:11.3.11 drupal-11.3.11 --no-dev --no-interaction
           # cd ~/static/june-8/drupal-11.3.11
           # composer require drush/drush
           # composer audit
           # (11.3.11)
```


## Check and compare versions built above as root

```sh
nc097:/data/disk/o3x/static/june-8# du -sh -- */
315M	commerce_kickstart-3.3.6-11.3.11/
170M	drupal-10.2.12/
178M	drupal-10.3.14/
186M	drupal-10.4.10/
187M	drupal-10.5.10/
188M	drupal-10.6.10/
183M	drupal-11.1.10/
199M	drupal-11.2.13/
205M	drupal-11.3.11/
521M	drupal_cms_installer-2.1.3-11.3.11/
232M	farm-4.0.2-11.3.11/
403M	localgov-4.0.3-11.3.11/
524M	openculturas-3.0.1-11.3.11/
273M	thunder-8.3.6-11.3.11/
572M	varbase-10.1.0-11.3.11/
nc097:/data/disk/o3x/static/june-8#
```

## Add them all as platforms in Ægir

Use paths like `june-8/drupal-11.3.11` and run tests for sites install, clone and migration.

## Notes on non-standard issues

Some codebases need manual fixes after the build. For example `openculturas` has wrong installation profile directory tree structure by default and doesn't have required `sites/example.sites.php` file, which needs to be copied there manually before you can install sites.


