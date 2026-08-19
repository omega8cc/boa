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
  commerce_kickstart-5.1.0-11.4.5
  drupal_cms_installer-2.1.3-11.4.5
  farm-4.0.4-11.3.14
  localgov-4.0.2-11.4.5
  openculturas-3.0.5-11.3.16
  openfed-13.6.6-10.6.15
  opigno_lms-3.2.7-10.6.15
  social-13.0.2-10.6.15
  thunder-8.4.0-11.4.5
  varbase-10.1.1-11.4.4
```

Raw cores, published to `/var/www/static/core`, latest patch of each supported minor:

```sh
  drupal-10.2.12    drupal-11.1.10
  drupal-10.3.14    drupal-11.2.14
  drupal-10.4.10    drupal-11.3.16
  drupal-10.5.12    drupal-11.4.5
  drupal-10.6.15
```

## Backdrop family

staticbuild is also the Backdrop-family builder. Backdrop is not Composer-based, so
it is built apart from the Drupal distros/cores — no Composer, no `/usr/bin/php`
switch, just git/wget/unzip — and always fetched at its newest upstream, so BOA
never falls behind. `staticbuild all` builds it alongside everything else; the
`backdrop` subcommand does a lightweight build + package + publish of only this
family:

```sh
  staticbuild backdrop           # build + package + publish only the Backdrop family
```

Four artefacts, always rebuilt at the latest upstream tag (pin any with the matching
`_*_TAG` in the config block):

- **backdrop** — Backdrop CMS core (`backdrop/backdrop`), from its latest GitHub
  release `backdrop.zip`. Repackaged versioned as `backdrop-<ver>.tar.gz` (extracts
  to `backdrop-<ver>/`), classified as a core and managed on the mirror exactly like
  the Drupal cores: every published version is retained, the resolved version is
  stamped to `backdrop.txt` (published only after its tarball, so the stamp never
  points at a missing file) — BOA names the platform from the stamp and fetches the
  matching tarball — and a version-less `backdrop.tar.gz` compat tarball of the newest
  release (extracting to `backdrop/`, the pre-versioning contract) is refreshed for
  already-deployed BOA releases. No contrib is baked into the versioned core
  tarballs — Valkey/Redis integration reaches platforms through the shared
  `o_contrib_backdrop` bundle (the `redis_backdrop` artefact below). Only the
  version-less compat tarball still carries a baked `modules/redis`, injected at
  tar time: the `/core/` shelf is shared by every release, and the pre-bundle
  releases consuming that name probe only `modules/redis`. Published
  to `/var/www/static/core`.
- **bee** — native Backdrop CLI (`backdrop-contrib/bee`), from its latest git tag,
  packaged version-less as `bee.tar.gz` (`bee.php` at the root). Published to
  `/var/www/static/dev/{dev,lts,pro}` — every box pulls its own tree dir.
- **backdrop-drush-extension** — the Backdrop Drush extension
  (`backdrop-contrib/backdrop-drush-extension`), from its latest git tag, packaged
  version-less as `backdrop-drush-extension.tar.gz` and shipped pristine (BOA applies
  its own PHP 5.6 de-hint and `__DIR__` include fix on deploy). Published to
  `/var/www/static/dev/{dev,lts,pro}` — every box pulls its own tree dir.
- **redis_backdrop** — the Backdrop redis contrib module (`backdrop-contrib/redis`),
  packaged versioned as `redis_backdrop-<tag>.tar.gz` wrapping a `redis_backdrop/`
  directory (the tarball's top-level name is the deployed directory name under the
  shared contrib store). Published to the per-tree contrib shelf
  `/var/www/static/dev/{dev,lts,pro}/contrib`. Unlike the other family members it
  is consumed by a pinned version on the BOA side — after publishing a newer tag,
  bump the pin in `OCTOPUS.sh.txt` and `BOA.sh.txt` together (a newer publish is
  inert until then; `staticbuild check` surfaces the drift as the `bd-redis` row).

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
  https://www.drupal.org/project/openfed
  https://www.drupal.org/project/opigno_lms
  https://www.drupal.org/project/social
  https://www.drupal.org/project/thunder
  https://www.drupal.org/project/varbase
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
cms        # composer create-project drupal/cms drupal_cms_installer-2.1.3-11.4.5 --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/MONTH-DAY/drupal_cms_installer-2.1.3-11.4.5
           # composer config --no-plugins allow-plugins true
           # composer update --no-install --no-scripts
           # composer install --no-dev
           # composer require drush/drush drupal/migrate_plus drupal/migrate_tools drupal/migrate_upgrade --no-scripts --no-interaction   # post-update-cmd exits non-zero; cms dev-requires drush, non-interactive confirms the move to require; migration pipeline contribs absent upstream
```

```sh
culturas   # composer create-project --remove-vcs drupal/openculturas_project openculturas-3.0.5-11.3.16 --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/MONTH-DAY/openculturas-3.0.5-11.3.16/
           # composer config --no-plugins allow-plugins true
           # composer config --json extra.composer-patches.ignore-dependency-patches '["openculturas/openculturas-distribution"]'  # drop dependency patches (stale + composer-patches 2.x cannot apply to dist installs)
           # composer update --no-install --no-scripts
           # composer install --no-dev
           # curl -fsS -o /tmp/err.patch https://www.drupal.org/files/issues/2023-06-29/entity_reference_revisions-2799479-fix-only.patch
           # (cd web/modules/contrib/entity_reference_revisions && patch -p1 < /tmp/err.patch)  # LOAD-BEARING: shipped views need it or every page 500s
           # cd web/profiles/contrib/openculturas-distribution
           # mv profile openculturas
           # mv openculturas ../ && mv * ../ && cd ../ && rm -rf openculturas-distribution
           # cp ~/static/MONTH-DAY/farm-4.0.4-11.3.14/web/sites/example.sites.php ~/static/MONTH-DAY/openculturas-3.0.5-11.3.16/web/sites/
```

```sh
commerce   # composer create-project -s dev centarro/commerce-kickstart-project commerce_kickstart-5.1.0-11.4.5 --no-dev --no-interaction --no-install --no-scripts
           # name by centarro/commerce_kickstart (the profile, 5.1.0); the project template stays dev-only
           # cd ~/static/MONTH-DAY/commerce_kickstart-5.1.0-11.4.5
           # composer config --no-plugins allow-plugins true
           # composer config --no-plugins --json policy.advisories.block false   # commerce_kickstart blocks advisory-affected deps
           # composer install --no-dev
           # composer require centarro/certified-projects
           # composer update --no-install --no-scripts
           # composer install --no-dev
```

```sh
localgov   # composer create-project drupal/localgov_project:^4 localgov-4.0.2-11.4.5 --no-dev --no-interaction --no-install --no-scripts
           # name by drupal/localgov (the distribution, 4.0.2); localgov_project versions separately
           # cd ~/static/MONTH-DAY/localgov-4.0.2-11.4.5
           # composer config --no-plugins allow-plugins true
           # composer update --no-install --no-scripts
           # composer install --no-dev
```

```sh
openfed    # The openfed-project template requires only three composer helpers; the whole
           # distribution (openfed/openfed 13.6.*) is merged in by composer-merge-plugin
           # from the template's composer.openfed.json, whose include list points INSIDE
           # packages the resolve itself installs (webform's + ckeditor_codemirror's
           # composer.libraries.json). The bootstrap install triggers the plugin's
           # nested in-process updates, which converge the tree - and then upstream's
           # recursive post-update-cmd (`composer install`, their include-file
           # self-heal) exits 4 against the mid-convergence lock, so the bootstrap's
           # rc is EXPECTED non-zero and tolerated. --no-scripts cannot avoid that
           # (measured): plugin event subscribers still run under --no-scripts and the
           # nested update they dispatch re-enables scripts on its own. The explicit
           # resolve+install pair after it is the real gate and must exit 0.
           # composer create-project openfed/openfed-project:^13 openfed-13.6.6-10.6.15 --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/MONTH-DAY/openfed-13.6.6-10.6.15
           # composer config --no-plugins allow-plugins true
           # composer config --no-plugins --json policy.advisories.block false
           # composer install --no-dev                    # bootstrap; rc 4 EXPECTED, tolerated
           # composer update --no-install --no-scripts    # complete lock incl. include-file libraries
           # composer install --no-dev
           # ACCEPTED TRADE: the platform ships drupal/entity_browser 2.15.0 with an open
           # XSS advisory (SA-CONTRIB-2026-094) - the profile pins entity_browser 2.15
           # exactly and the fixed release (2.16.0) is outside it, so advisory blocking
           # must stay off for this build.
           # name by openfed/openfed read from the LOCK (the drupal.org release number);
           # profile openfed, docroot docroot/; the profile pins core-recommended ~10.6,
           # so no older-core fallback applies; builds under php83 (its catalogue cap)
```

```sh
opigno     # Opigno's documented create-project is broken as shipped, in three ways the
           # build corrects. (1) The template replaces h5p/h5p-core + h5p/h5p-editor
           # without providing them, so \H5PFrameworkInterface never reaches disk and
           # every install fatals in h5p_install() (opigno_lms #3574405): drop the
           # replace block. (2) h5p-core 1.28.0 added an interface method drupal/h5p
           # 2.0.0-beta1 does not implement (h5p #3578071): require h5p/h5p-core:1.27.*
           # (inside the module's own ^1.27). (3) Twig 3.22+ rejects
           # opigno_learning_path's empty getOperators() on the first front-page render
           # (#3561556, RTBC, in no release): apply the issue patch, fail closed.
           # composer create-project opigno/opigno-composer opigno_lms-3.2.7-10.6.15 --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/MONTH-DAY/opigno_lms-3.2.7-10.6.15
           # composer config --no-plugins allow-plugins true
           # composer config --no-plugins --json policy.advisories.block false
           # composer config --unset replace
           # composer require --no-update --no-scripts h5p/h5p-core:'1.27.*'
           # composer update --no-install --no-scripts
           # composer install --no-dev
           # cd web && patch -p1 < the #3561556 getOperators patch
           # ACCEPTED TRADE: the platform ships dompdf 2.0.8 with open advisories -
           # the profile pins dompdf ~2.0.0 and the fixed line (3.x) is outside it,
           # so advisory blocking must stay off for this build.
           # name by opigno/opigno_lms read from the LOCK; profile opigno_lms,
           # docroot web/; builds under php83 (its catalogue cap)
```

```sh
social     # Open Social ships NO create-project template for its current major:
           # goalgorilla/social_template is frozen at 12.4.2 on core 10.2.6. Take that
           # template as the chassis - it owns the html/ docroot, the scaffold locations
           # and the installer-paths upstream itself defined - and move only the
           # distribution to the current major.
           # composer create-project goalgorilla/social_template:dev-master social-13.0.2-10.6.15 --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/MONTH-DAY/social-13.0.2-10.6.15
           # composer config --no-plugins allow-plugins true
           # composer require --no-update --no-scripts goalgorilla/open_social:^13
           # composer update --no-install --no-scripts
           # composer install --no-dev
           # name by goalgorilla/open_social read from the LOCK (13.0.2) - upstream's
           # 13.0.2 tag still declares version '13.0.1' inside social.info.yml
           # builds under php83: 13.0.2 requires php ^8.3 and SOC is capped at 8.3
           # docroot is html/ (not web/), and a fresh install's front page is bare
```

```sh
thunder    # composer create-project thunder/thunder-project thunder-8.4.0-11.4.5 --no-dev --no-interaction --no-install --no-scripts
           # name by thunder/thunder-distribution (8.4.0); thunder/thunder-project versions separately (5.0.0)
           # cd ~/static/MONTH-DAY/thunder-8.4.0-11.4.5
           # composer config --no-plugins allow-plugins true
           # composer update --no-install --no-scripts
           # composer install --no-dev
```

```sh
varbase    # RE-ENABLED 2026-08-11: upstream fixed the template in July 2026 (core pinned
           # explicitly + committed lock), after a year of drift that made every fresh
           # build uninstallable. Builds the stable 10 line; the 11.0 line is beta and
           # uses a different docroot (web/ instead of docroot/) - do not switch until
           # 11.0.0 is stable AND the catalogue web_dir is updated with it.
           # composer create-project Vardot/varbase-project:~10 varbase-VERSION-CORE --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/MONTH-DAY/varbase-VERSION-CORE
           # composer config --no-plugins allow-plugins true
           # composer update --no-install --no-scripts
           # composer install --no-dev
           # name by vardot/varbase from the lock (the drupal.org release number)
           # docroot is docroot/; each recipes/ dir needs a default/content subdir
           # (the build creates them); builds under php84
```

Vanilla cores, latest patch of each supported minor (full install, add drush, audit):

```sh
vanilla    # for each minor 10.2 10.3 10.4 10.5 10.6 11.1 11.2 11.3 11.4:
           # composer create-project drupal/recommended-project:<minor>.* drupal-<version> --no-dev --no-interaction
           # cd drupal-<version> && composer require drush/drush && composer audit
           # built: 10.2.12 10.3.14 10.4.10 10.5.12 10.6.15 11.1.10 11.2.14 11.3.16 11.4.5
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

Use paths like `MONTH-DAY/drupal-11.4.5` and run tests for site install, clone and migration.

## Notes on non-standard issues

Some codebases need extra handling; staticbuild does all of this automatically.

- **allow-plugins** — allow all Composer plugins (`composer config allow-plugins true`);
  the distros pull composer/installers, cweagans/composer-patches, installers-extender,
  etc., and current Composer blocks any unlisted plugin.
- **openculturas** — its install profile has a wrong directory tree by default and ships
  no `sites/example.sites.php` (copy one in). Its dependency patches are dropped
  (`extra.composer-patches.ignore-dependency-patches`): several are stale against the
  core the distribution itself requires, and composer-patches 2.x cannot apply patches
  to dist-installed packages at all (its GitPatcher skips any package dir without
  `.git`, its FreeformPatcher needs per-patch config). One patch is load-bearing and is
  applied with GNU `patch` after the build instead, fail-closed: the shipped views
  reference `entity_reference_revisions` relationship handlers that only exist with the
  ERR issue-2799479 patch — without it every front page request throws
  `ViewsData->get()` InvalidArgumentException and the site serves 500s.
- **commerce** — commerce_kickstart enables Composer security-advisory blocking, which
  refuses advisory-affected core/deps; disable it (`policy.advisories.block false`) for the
  test build.
- **thunder** — `thunder/thunder-project` (the template) versions independently (e.g. 5.0.0)
  from the actual distribution `thunder/thunder-distribution` (e.g. 8.4.0); name by the latter.
- **cms** — drupal_cms's post-update-cmd cleanup script exits non-zero; run its drush
  require with `--no-scripts`. The same require adds the migration pipeline contribs
  (`migrate_plus`, `migrate_tools`, `migrate_upgrade`) — upstream drupal/cms ships none
  of them, and core's migrate stack lives in drupal/core; inert until a site enables them.
  The build also corrects pathauto's `d7_pathauto_patterns` migration definition
  (adds `source_module: pathauto`, upstream pathauto #3588684): Drupal 11 prefers the
  plugin's PHP attribute, which lost `source_module` in the annotation-to-attribute
  conversion, and without the correction migrate_drupal validation refuses every
  Drupal 7 → Drupal CMS upgrade at the credentials step. Guarded no-op once a tagged
  pathauto release carries the fix.
- **stale core patches / older cores** — if a distro fails on the newest core, retry pinned
  to progressively older core minors and keep the newest that works.
