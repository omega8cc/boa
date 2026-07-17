# How we build newer codebases for testing

The newer Drupal core and distribution codebases we build for install / clone /
migration testing and publish to the static mirror (`/var/www/static/{core,distro}`).
Run on the mirror source VM.

## Automated: staticbuild

`aegir/tools/bin/staticbuild` automates the whole procedure below. It derives every
version from the actual build (nothing is hardcoded), auto-discovers the core minors,
handles the per-distro quirks (see Notes), packages, and publishes. Run it as root:

```sh
  staticbuild check              # report the latest upstream versions a build would pull
  staticbuild all                # build every distro + core, package, publish
  staticbuild build [name ...]   # build all, or only named targets
  staticbuild package            # clean + tar (cores keep core/profiles, distros strip)
  staticbuild distribute         # copy tarballs to /var/www/static/{distro,core,dev/{dev,lts,pro}}
```

Configuration (Composer specs + core floor/exclude) is the block at the top of the
script. If a distro fails to build on the newest core, it is retried on progressively
older core minors and the newest that works is kept. The manual steps below document
what it does.

## What it builds (example run; versions are derived per build)

Distributions, published to `/var/www/static/distro`:

```sh
  commerce_kickstart-5.1.0-11.4.4
  drupal_cms_installer-2.1.3-11.4.4
  farm-4.0.4-11.3.14
  localgov-4.0.2-11.4.4
  openculturas-3.0.3-11.3.14
  thunder-8.4.0-11.4.4
```

Raw cores, published to `/var/www/static/core`, latest patch of each supported minor:

```sh
  drupal-10.2.12    drupal-11.1.10
  drupal-10.3.14    drupal-11.2.14
  drupal-10.4.10    drupal-11.3.14
  drupal-10.5.12    drupal-11.4.4
  drupal-10.6.13
```

## Backdrop family

staticbuild is also the Backdrop-family builder. Backdrop is not Composer-based, so
it is built apart from the Drupal distros/cores — no Composer, no `/usr/bin/php`
switch, just git/wget/unzip — and always fetched at its newest upstream, published
version-less so BOA never falls behind. `staticbuild all` builds it alongside
everything else; the `backdrop` subcommand does a lightweight build + package +
publish of only this family:

```sh
  staticbuild backdrop           # build + package + publish only the Backdrop family
```

Three artefacts, always rebuilt at the latest upstream tag (pin any with the matching
`_*_TAG` in the config block):

- **backdrop** — Backdrop CMS core (`backdrop/backdrop`), from its latest GitHub
  release `backdrop.zip`. Repackaged version-less as `backdrop.tar.gz` (extracts to
  `backdrop/`), classified as a core, with the resolved version stamped to
  `backdrop.txt` so BOA can name the platform. The Backdrop redis contrib module is
  baked into `modules/` for Valkey/Redis object-cache support. Published to
  `/var/www/static/core`.
- **bee** — native Backdrop CLI (`backdrop-contrib/bee`), from its latest git tag,
  packaged version-less as `bee.tar.gz` (`bee.php` at the root). Published to
  `/var/www/static/dev/{dev,lts,pro}` — every box pulls its own tree dir.
- **backdrop-drush-extension** — the Backdrop Drush extension
  (`backdrop-contrib/backdrop-drush-extension`), from its latest git tag, packaged
  version-less as `backdrop-drush-extension.tar.gz` and shipped pristine (BOA applies
  its own PHP 5.6 de-hint and `__DIR__` include fix on deploy). Published to
  `/var/www/static/dev/{dev,lts,pro}` — every box pulls its own tree dir.

## Manual procedure (reference)

### Prepare environment

```sh
  su -s /bin/bash - o8
  mkdir -p ~/static/MONTH-DAY/
  cd ~/static/MONTH-DAY/
  composer clearcache
  ln -sf /opt/php85/bin/php /usr/bin/php
```

### Visit for latest versions check

```sh
  https://www.drupal.org/project/drupal/releases/
  https://www.drupal.org/project/cms
  https://www.drupal.org/project/commerce
  https://www.drupal.org/project/farm
  https://www.drupal.org/project/localgov
  https://www.drupal.org/project/openculturas
  https://www.drupal.org/project/thunder
```

### Build them one by one and document results

Common shape for the create-project distros (farmOS is a release tarball instead).
`allow-plugins true` matters: the distros pull composer/installers, composer-patches,
etc., which current Composer blocks unless allowed.

```sh
farmos     # farm-4.0.4-11.3.14  (farmOS caps core at 11.3)
           # visit: https://github.com/farmOS/farmOS/releases
           # wget https://github.com/farmOS/farmOS/releases/download/4.0.4/farmOS-4.0.4.tar.gz
           # tar -xzf farmOS-4.0.4.tar.gz && mv farmOS farm-4.0.4-11.3.14
           # cd ~/static/MONTH-DAY/farm-4.0.4-11.3.14
           # composer config --no-plugins allow-plugins true
           # composer update --no-install --no-scripts
           # composer install --no-dev
```

```sh
cms        # composer create-project drupal/cms drupal_cms_installer-2.1.3-11.4.4 --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/MONTH-DAY/drupal_cms_installer-2.1.3-11.4.4
           # composer config --no-plugins allow-plugins true
           # composer update --no-install --no-scripts
           # composer install --no-dev
           # composer require drush/drush --no-scripts --no-interaction   # post-update-cmd exits non-zero; cms dev-requires drush, non-interactive confirms the move to require
```

```sh
culturas   # composer create-project --remove-vcs drupal/openculturas_project openculturas-3.0.3-11.3.14 --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/MONTH-DAY/openculturas-3.0.3-11.3.14/
           # composer config --no-plugins allow-plugins true
           # composer config --json extra.composer-patches.ignore-dependency-patches '["openculturas/openculturas-distribution"]'  # build unpatched (stale core patch)
           # composer update --no-install --no-scripts
           # composer install --no-dev
           # cd web/profiles/contrib/openculturas-distribution
           # mv profile openculturas
           # mv openculturas ../ && mv * ../ && cd ../ && rm -rf openculturas-distribution
           # cp ~/static/MONTH-DAY/farm-4.0.4-11.3.14/web/sites/example.sites.php ~/static/MONTH-DAY/openculturas-3.0.3-11.3.14/web/sites/
```

```sh
commerce   # composer create-project -s dev centarro/commerce-kickstart-project commerce_kickstart-5.1.0-11.4.4 --no-dev --no-interaction --no-install --no-scripts
           # name by centarro/commerce_kickstart (the profile, 5.1.0); the project template stays dev-only
           # cd ~/static/MONTH-DAY/commerce_kickstart-5.1.0-11.4.4
           # composer config --no-plugins allow-plugins true
           # composer config --no-plugins --json policy.advisories.block false   # commerce_kickstart blocks advisory-affected deps
           # composer install --no-dev
           # composer require centarro/certified-projects
           # composer update --no-install --no-scripts
           # composer install --no-dev
```

```sh
localgov   # composer create-project drupal/localgov_project:^4 localgov-4.0.2-11.4.4 --no-dev --no-interaction --no-install --no-scripts
           # name by drupal/localgov (the distribution, 4.0.2); localgov_project versions separately
           # cd ~/static/MONTH-DAY/localgov-4.0.2-11.4.4
           # composer config --no-plugins allow-plugins true
           # composer update --no-install --no-scripts
           # composer install --no-dev
```

```sh
thunder    # composer create-project thunder/thunder-project thunder-8.4.0-11.4.4 --no-dev --no-interaction --no-install --no-scripts
           # name by thunder/thunder-distribution (8.4.0); thunder/thunder-project versions separately (5.0.0)
           # cd ~/static/MONTH-DAY/thunder-8.4.0-11.4.4
           # composer config --no-plugins allow-plugins true
           # composer update --no-install --no-scripts
           # composer install --no-dev
```

<!-- varbase DISABLED: the upstream Vardot/varbase-project template no longer builds an
     installable site (a fresh ~10 resolve pins core 11.2.14, which the varbase profile
     ~11.3.0 rejects; pinned to 11.3.x a drifted dep fatals during install; 11.0.0-alpha3
     OOMs then hits a canvas final-class fatal). The last working varbase-10.1.0-11.3.12
     build is kept on the mirror; do not rebuild until upstream is fixed. See staticbuild. -->

Vanilla cores, latest patch of each supported minor (full install, add drush, audit):

```sh
vanilla    # for each minor 10.2 10.3 10.4 10.5 10.6 11.1 11.2 11.3 11.4:
           # composer create-project drupal/recommended-project:<minor>.* drupal-<version> --no-dev --no-interaction
           # cd drupal-<version> && composer require drush/drush && composer audit
           # built: 10.2.12 10.3.14 10.4.10 10.5.12 10.6.13 11.1.10 11.2.14 11.3.14 11.4.4
```

### Clean up artefacts before packaging

```sh
  cd ~/static/MONTH-DAY/
  rm -f  */*/modules/o_contrib*
  rm -rf */*/sites/all/drush
  rm -f  */*/sites/all/modules/*
  rm -f  */*/sites/sites.php
  rm -f  */*/local_drush_unlocked.pid
  rm -f  */*/sites/development.services.yml
  rm -f  */*/sites/all/libraries/*.pid
```

### Package the platforms

Gzip the raw-core platforms first, keeping their `core/profiles`:

```sh
  cd ~/static/MONTH-DAY/
  for d in drupal-*/ ; do tar -czf "${d%/}.tar.gz" "${d%/}" ; done
```

Then strip the stock core profiles from the distributions (they ship their own
install profile), then gzip the remaining (distribution) platforms:

```sh
  rm -rf */*/core/profiles/*
  for d in */ ; do case "${d%/}" in drupal-*) continue ;; esac ; tar -czf "${d%/}.tar.gz" "${d%/}" ; done
```

### Publish the tarballs to the static mirror

```sh
  cp -a ~/static/MONTH-DAY/drupal-*.tar.gz            /var/www/static/core/
  cp -a ~/static/MONTH-DAY/*.tar.gz                   /var/www/static/distro/   # then remove the drupal-* copies from distro/
```

Raw cores (`drupal-*`) go to `core/`; everything else goes to `distro/`.

## Add them all as platforms in Ægir

Use paths like `MONTH-DAY/drupal-11.4.4` and run tests for site install, clone and migration.

## Notes on non-standard issues

Some codebases need extra handling; staticbuild does all of this automatically.

- **allow-plugins** — allow all Composer plugins (`composer config allow-plugins true`);
  the distros pull composer/installers, cweagans/composer-patches, installers-extender,
  etc., and current Composer blocks any unlisted plugin.
- **openculturas** — its install profile has a wrong directory tree by default and ships
  no `sites/example.sites.php` (copy one in). Its core patch no longer applies on current
  core and composer-patches 2.x has no per-patch skip, so build it unpatched by ignoring
  its distribution's patches (`extra.composer-patches.ignore-dependency-patches`).
- **commerce** — commerce_kickstart enables Composer security-advisory blocking, which
  refuses advisory-affected core/deps; disable it (`policy.advisories.block false`) for the
  test build.
- **thunder** — `thunder/thunder-project` (the template) versions independently (e.g. 5.0.0)
  from the actual distribution `thunder/thunder-distribution` (e.g. 8.4.0); name by the latter.
- **cms** — drupal_cms's post-update-cmd cleanup script exits non-zero; run its drush
  require with `--no-scripts`.
- **stale core patches / older cores** — if a distro fails on the newest core, retry pinned
  to progressively older core minors and keep the newest that works.
