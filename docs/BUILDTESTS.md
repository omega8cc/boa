# How we build newer codebases for testing

Manual reference procedure for building the newer Drupal core and distribution
codebases we use for install / clone / migration testing, updated for current
Composer. Run it on the mirror source VM.

## Prepare environment

```sh
  su -s /bin/bash - o8
  mkdir -p ~/static/MONTH-DAY/
  cd ~/static/MONTH-DAY/
  composer clearcache
  ln -sf /opt/php85/bin/php /usr/bin/php
```

## Visit for latest versions check

```sh
  https://www.drupal.org/project/drupal/releases/
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
farmos     # farm-4.0.3-11.3.12
           # visit: https://github.com/farmOS/farmOS/releases
           # wget https://github.com/farmOS/farmOS/releases/download/4.0.3/farmOS-4.0.3.tar.gz
           # tar -xzf farmOS-4.0.3.tar.gz
           # mv farmOS farm-4.0.3-11.3.12
           # cd ~/static/MONTH-DAY/farm-4.0.3-11.3.12
           # composer config --no-plugins allow-plugins.symfony/runtime true
           # composer config --no-plugins allow-plugins.drupal/core-composer-scaffold true
           # composer update --no-install --no-scripts
           # composer install --no-dev
           # (11.3.12)
```

```sh
cms        # composer create-project drupal/cms drupal_cms_installer-2.1.3-11.3.12 --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/MONTH-DAY/drupal_cms_installer-2.1.3-11.3.12
           # composer config --no-plugins allow-plugins.symfony/runtime true
           # composer config --no-plugins allow-plugins.drupal/core-composer-scaffold true
           # composer update --no-install --no-scripts
           # composer install --no-dev
           # composer require drush/drush
           # (11.3.12)
```

```sh
culturas   # composer create-project --remove-vcs drupal/openculturas_project openculturas-3.0.2-11.3.12 --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/MONTH-DAY/openculturas-3.0.2-11.3.12/
           # composer config --no-plugins allow-plugins.symfony/runtime true
           # composer config --no-plugins allow-plugins.drupal/core-composer-scaffold true
           # composer update --no-install --no-scripts
           # composer install --no-dev
           # cd ~/static/MONTH-DAY/openculturas-3.0.2-11.3.12/web/profiles/contrib/openculturas-distribution
           # mv profile openculturas
           # mv openculturas ~/static/MONTH-DAY/openculturas-3.0.2-11.3.12/web/profiles/contrib/
           # mv * ~/static/MONTH-DAY/openculturas-3.0.2-11.3.12/web/profiles/contrib/
           # cd ~/static/MONTH-DAY/openculturas-3.0.2-11.3.12/web/profiles/contrib/
           # rm -rf openculturas-distribution
           # cp ~/static/MONTH-DAY/farm-4.0.3-11.3.12/web/sites/example.sites.php ~/static/MONTH-DAY/openculturas-3.0.2-11.3.12/web/sites/
           # (11.3.12)
```

```sh
commerce   # composer create-project -s dev centarro/commerce-kickstart-project commerce_kickstart-3.3.6-11.3.12 --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/MONTH-DAY/commerce_kickstart-3.3.6-11.3.12
           # composer config --no-plugins allow-plugins.symfony/runtime true
           # composer config --no-plugins allow-plugins.drupal/core-composer-scaffold true
           # composer install --no-dev
           # composer require centarro/certified-projects
           # composer update --no-install --no-scripts
           # composer install --no-dev
           # (11.3.12)
```

```sh
localgov   # composer create-project drupal/localgov_project:^4.0 localgov-4.0.3-11.3.12 --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/MONTH-DAY/localgov-4.0.3-11.3.12
           # composer config --no-plugins allow-plugins.symfony/runtime true
           # composer config --no-plugins allow-plugins.drupal/core-composer-scaffold true
           # composer update --no-install --no-scripts
           # composer install --no-dev
           # (11.3.12)
```

```sh
thunder    # composer create-project thunder/thunder-project thunder-8.3.6-11.3.12 --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/MONTH-DAY/thunder-8.3.6-11.3.12
           # composer config --no-plugins allow-plugins.symfony/runtime true
           # composer config --no-plugins allow-plugins.drupal/core-composer-scaffold true
           # composer update --no-install --no-scripts
           # composer install --no-dev
           # (11.3.12)
```

```sh
varbase    # composer create-project Vardot/varbase-project:~10 varbase-10.1.0-11.3.12 --no-dev --no-interaction --no-install --no-scripts
           # ln -sf /opt/php84/bin/php /usr/bin/php
           # cd ~/static/MONTH-DAY/varbase-10.1.0-11.3.12
           # composer config --no-plugins allow-plugins.symfony/runtime true
           # composer config --no-plugins allow-plugins.drupal/core-composer-scaffold true
           # composer update --no-install --no-scripts
           # composer install --no-dev
           # cd ~/static/MONTH-DAY/varbase-10.1.0-11.3.12/docroot
           # find -name recipes | awk '{print $1"/default/content"}' | xargs -I {} mkdir -p {}
           # (11.3.12)
```

```sh
vanilla    # composer create-project drupal/recommended-project:10.2.12 drupal-10.2.12 --no-dev --no-interaction
           # cd ~/static/MONTH-DAY/drupal-10.2.12
           # composer require drush/drush
           # composer audit
           # (10.2.12)
```

```sh
vanilla    # composer create-project drupal/recommended-project:10.3.14 drupal-10.3.14 --no-dev --no-interaction
           # cd ~/static/MONTH-DAY/drupal-10.3.14
           # composer require drush/drush
           # composer audit
           # (10.3.14)
```

```sh
vanilla    # composer create-project drupal/recommended-project:10.4.10 drupal-10.4.10 --no-dev --no-interaction
           # cd ~/static/MONTH-DAY/drupal-10.4.10
           # composer require drush/drush
           # composer audit
           # (10.4.10)
```

```sh
vanilla    # composer create-project drupal/recommended-project:10.5.12 drupal-10.5.12 --no-dev --no-interaction
           # cd ~/static/MONTH-DAY/drupal-10.5.12
           # composer require drush/drush
           # composer audit
           # (10.5.12)
```

```sh
vanilla    # composer create-project drupal/recommended-project:10.6.11 drupal-10.6.11 --no-dev --no-interaction
           # cd ~/static/MONTH-DAY/drupal-10.6.11
           # composer require drush/drush
           # composer audit
           # (10.6.11)
```

```sh
vanilla    # composer create-project drupal/recommended-project:11.1.10 drupal-11.1.10 --no-dev --no-interaction
           # cd ~/static/MONTH-DAY/drupal-11.1.10
           # composer require drush/drush
           # composer audit
           # (11.1.10)
```

```sh
vanilla    # composer create-project drupal/recommended-project:11.2.14 drupal-11.2.14 --no-dev --no-interaction
           # cd ~/static/MONTH-DAY/drupal-11.2.14
           # composer require drush/drush
           # composer audit
           # (11.2.14)
```

```sh
vanilla    # composer create-project drupal/recommended-project:11.3.12 drupal-11.3.12 --no-dev --no-interaction
           # cd ~/static/MONTH-DAY/drupal-11.3.12
           # composer require drush/drush
           # composer audit
           # (11.3.12)
```

## Check and compare versions built above as root

```sh
o8@host:~/static/MONTH-DAY$ du -sh -- */
310M	commerce_kickstart-3.3.6-11.3.12/
169M	drupal-10.2.12/
178M	drupal-10.3.14/
185M	drupal-10.4.10/
187M	drupal-10.5.12/
187M	drupal-10.6.11/
182M	drupal-11.1.10/
188M	drupal-11.2.14/
194M	drupal-11.3.12/
521M	drupal_cms_installer-2.1.3-11.3.12/
232M	farm-4.0.3-11.3.12/
402M	localgov-4.0.3-11.3.12/
523M	openculturas-3.0.2-11.3.12/
272M	thunder-8.3.6-11.3.12/
570M	varbase-10.1.0-11.3.12/
```

## Clean up artefacts before packaging

```sh
  cd ~/static/MONTH-DAY/
  rm -f */*/modules/o_contrib*
  rm -f -r */*/sites/all/drush
  rm -f */*/sites/all/modules/*
  rm -f */*/sites/sites.php
  rm -f */*/local_drush_unlocked.pid
  rm -f */*/sites/development.services.yml
  rm -f */*/sites/all/libraries/*.pid
```

## Package the platforms

Gzip the raw-core platforms first, keeping their `core/profiles`:

```sh
  cd ~/static/MONTH-DAY/
  tar -czf drupal-10.2.12.tar.gz drupal-10.2.12
  tar -czf drupal-10.3.14.tar.gz drupal-10.3.14
  tar -czf drupal-10.4.10.tar.gz drupal-10.4.10
  tar -czf drupal-10.5.12.tar.gz drupal-10.5.12
  tar -czf drupal-10.6.11.tar.gz drupal-10.6.11
  tar -czf drupal-11.1.10.tar.gz drupal-11.1.10
  tar -czf drupal-11.2.14.tar.gz drupal-11.2.14
  tar -czf drupal-11.3.12.tar.gz drupal-11.3.12
```

Then strip the stock core profiles from the distributions (they ship their own
install profile):

```sh
  rm -f -r */*/core/profiles/*
```

Then gzip the remaining (distribution) platforms:

```sh
  tar -czf commerce_kickstart-3.3.6-11.3.12.tar.gz commerce_kickstart-3.3.6-11.3.12
  tar -czf drupal_cms_installer-2.1.3-11.3.12.tar.gz drupal_cms_installer-2.1.3-11.3.12
  tar -czf farm-4.0.3-11.3.12.tar.gz farm-4.0.3-11.3.12
  tar -czf localgov-4.0.3-11.3.12.tar.gz localgov-4.0.3-11.3.12
  tar -czf openculturas-3.0.2-11.3.12.tar.gz openculturas-3.0.2-11.3.12
  tar -czf thunder-8.3.6-11.3.12.tar.gz thunder-8.3.6-11.3.12
  tar -czf varbase-10.1.0-11.3.12.tar.gz varbase-10.1.0-11.3.12
```

## Publish the tarballs to the static mirror

Copy all non-raw-core (distribution) tarballs:

```sh
  cd /var/www/static/distro
  cp -a ~/static/MONTH-DAY/commerce_kickstart-3.3.6-11.3.12.tar.gz .
  cp -a ~/static/MONTH-DAY/drupal_cms_installer-2.1.3-11.3.12.tar.gz .
  cp -a ~/static/MONTH-DAY/farm-4.0.3-11.3.12.tar.gz .
  cp -a ~/static/MONTH-DAY/localgov-4.0.3-11.3.12.tar.gz .
  cp -a ~/static/MONTH-DAY/openculturas-3.0.2-11.3.12.tar.gz .
  cp -a ~/static/MONTH-DAY/thunder-8.3.6-11.3.12.tar.gz .
  cp -a ~/static/MONTH-DAY/varbase-10.1.0-11.3.12.tar.gz .
```

Copy all raw-core tarballs:

```sh
  cd /var/www/static/core
  cp -a ~/static/MONTH-DAY/drupal-10.2.12.tar.gz .
  cp -a ~/static/MONTH-DAY/drupal-10.3.14.tar.gz .
  cp -a ~/static/MONTH-DAY/drupal-10.4.10.tar.gz .
  cp -a ~/static/MONTH-DAY/drupal-10.5.12.tar.gz .
  cp -a ~/static/MONTH-DAY/drupal-10.6.11.tar.gz .
  cp -a ~/static/MONTH-DAY/drupal-11.1.10.tar.gz .
  cp -a ~/static/MONTH-DAY/drupal-11.2.14.tar.gz .
  cp -a ~/static/MONTH-DAY/drupal-11.3.12.tar.gz .
```

## Add them all as platforms in Ægir

Use paths like `MONTH-DAY/drupal-11.3.12` and run tests for site install, clone and migration.

## Notes on non-standard issues

Some codebases need manual fixes after the build. For example `openculturas` has a
wrong installation profile directory tree structure by default and does not ship the
required `sites/example.sites.php` file, which must be copied there manually (see the
`culturas` block above) before you can install sites.
