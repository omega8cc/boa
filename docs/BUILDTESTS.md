# How we build the distribution catalogue and test codebases

The newer Drupal core and distribution codebases we build and publish to the static
mirror (`/var/www/static/{core,distro}`). They are the catalogue every Octopus instance
installs, declared for demonstration and compatibility testing only, not for production:
tenants run production on their own builds in `~/static`, and security updates for the
catalogue are best effort: each build applies the fixed releases the constraints allow.
The same cores and distributions are what we
install, clone and migrate in testing. Run on the mirror source VM.

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
                                 # (a same-name distro or vanilla core tarball whose lock changed
                                 #  replaces the published one unless it adds advisories or
                                 #  cannot be checked for them; then it is refused and the
                                 #  run ends with exit 3)
  staticbuild -O distribute <platform> ...
                                 # the same, overwriting the named platforms' published tarballs
  staticbuild catalogue [tree]   # audit each tree's PUBLISHED catalogue against the distro mirror
                                 # (PRODUCER=none: hand-published, nothing here rebuilds it; a tree that
                                 #  cannot be read is INCONCLUSIVE and exits non-zero, never "0 missing")
  staticbuild advisories [tree]  # read-only: audit the lock of every PUBLISHED catalogue platform
                                 # (distributions and the Drupal 9-11 cores) against today's
                                 # advisories, and list BOA's own non-Composer contrib (exits
                                 # non-zero only when something could not be audited)
```

Configuration (Composer specs + core floor/exclude) is the block at the top of the
script. If a distro fails to build on the newest core, it is retried on progressively
older core minors and the newest that works is kept. The manual steps below document
what it does.

Options precede the action: `-d MM-DD`, `-u USER`, `-f`, `-C`, `-O` (with `distribute`
only), and `--debug`.

By default `build`, `package`, `distribute`, `all` and the family
actions print a header naming the run's log and then **one row per platform** (build
result, advisories left and fixed, what happened on the mirror, and a two- or
three-word note only when the row needs attention, such as `adds advisories` or
`patch skipped`), plus a footer with the command for refused tarballs and the end of a
failed build's log. Composer, git and tar output, every advisory id and the lock hashes
go to the log under `/var/backups/reports/staticbuild/<user>/<MM-DD>/` (root only);
`--debug` streams them instead.

The two pinned catalogue platforms, `ezcontent` (EZC) and `commerce_base` (CK2), are
build targets too: with no upstream recipe left, each starts from its own published
tarball (the local shelf, else the distro mirror) and only the advisory fix step
changes it, so distribution, core and name stay and the rebuild replaces the published
copy unless it adds advisories or cannot be checked for them. Their core minors are
past security support, so core advisories remain.

CK2 resolves one package from a
GitHub repository; when GitHub refuses anonymous requests (rate limit), its row says
so, and a GitHub token in the build user's Composer configuration lifts the limit.

### Advisories: audited, not blocked

Composer's security-advisory blocking stays **off** for the distributions that resolve
their dependencies (`policy.advisories.block false`, set with the other build config;
current Composer blocks by default, and commerce_kickstart enables it itself). varbase
installs from upstream's lock, which Composer does not filter. One upstream advisory must
not halt a catalogue build, and blocking would also defeat the older-core fallback.
Instead each build applies what fixes it can, and what shipped is recorded, twice:

- **At build time.** A finished distribution first gets a fix step: each package with
  an advisory moves to the newest release the distribution's own constraints allow, one
  package at a time with its non-root dependencies (`--with-dependencies
  --minimal-changes`), so the core pins stay put.

  A move that would change Drupal core
  is put back (a newer core is a new platform name, a catalogue move with a BOA
  release); the build's distribution package and any module it patches by hand are
  left alone; the result installs once, and if it does not, the build fails and the
  published copy stays. The fixed amazee.io provider releases declare `ext-pdo_pgsql`, so
  that one platform requirement is ignored, as for varbase.

  Then every package the tree's `vendor/composer/installed.json` lists must be on disk.
  Composer's patch plugin can remove a package to patch it again, and a later partial
  Composer run never puts it back (EzContent lost `entity_browser` and `yoast_seo` after
  its fix step, Opigno `calendar` and `h5p` after its `drush/drush` require). A missing
  package is installed again from the lock in the tree's own dev scope; one still
  missing fails the build.
- Every finished distribution and vanilla core is then audited (`composer audit
  --locked`, never fatal) and the report is written beside its tarball as
  `~/static/MONTH-DAY/<platform>.advisories`: the count, one line per finding (id,
  package, locked version, CVE, link), a closing line on require-dev, and what the fix
  step moved and could not move, with the reason. The summary row shows the count left
  and how many the build fixed. An audit that cannot run (no lock, an advisory source
  unreachable) marks the row `audit failed`, and the build still succeeds.
- **On the published set.** `staticbuild advisories [tree ...]` reads every catalogue
  entry of each published tree: the distributions (the list `staticbuild catalogue`
  checks, fetched from `distro/`) and the Drupal 9, 10 and 11 core platforms
  (`DL9`, `DX*`, `DE*`, fetched from `core/`). It pulls `composer.lock` and
  `vendor/composer/installed.json` out of each published tarball's stream and audits
  them against today's advisories, since advisories keep arriving after a build.

  It
  prints one row per tarball with the trees that list it and its advisory count; each
  tarball is audited once per run, and `--debug` adds every advisory id under its row.
  The Drupal 6/7 cores are BOA's own forks, outside Composer, and are not audited here.
  Read-only; it needs curl, tar, composer and php, not root.

Both audits run on a disposable copy of the platform's lock, never inside the
platform. The copy's `composer.json` carries nothing of the platform's: no scripts
(Composer runs a composer.json's `init` and `pre-command-run` scripts even for
`audit`), no config (ignore lists, `cache-dir`), no repositories (a `packagist.org`
false entry would hide advisories).

It declares only `https://packages.drupal.org/8`,
because drupal.org's **contrib** advisories reach Composer only through that
repository: a lock audited against Packagist alone reports none of them (measured with
`drupal/entity_browser` 2.15.0 and SA-CONTRIB-2026-094). The audit runs with
`--no-plugins --no-scripts` and a Composer home of its own, so no global config applies
either.

A platform whose `installed.json` says require-dev was not installed is audited with
`--no-dev`; otherwise the whole lock is. Composer's filter-list hits (its malware
list) count as findings, with the list name before the id. The count is Composer's
own, so a core advisory that both drupal.org (`SA-CORE-*`) and Packagist's advisory
database (`PKSA-*`) carry is listed under both ids.

BOA's own contrib — `robotstxt`, `readonlymode` and the Redis integration module the
`o_contrib_*` bundles link into every Drupal 8+ platform (`_satellite_download_o_contrib_*`
in `lib/functions/satellite.sh.inc`) — lives outside Composer, so no `composer audit`
sees it. `staticbuild advisories` lists those modules per bundle (once when the trees
agree) with the versions the published tree fetches: check them against drupal.org's
advisories by hand. A hit there is fixed in `satellite.sh.inc` and ships with BOA,
not through staticbuild.

By hand, the same audit of a built platform is:

```sh
  mkdir /tmp/audit && cp ~/static/MONTH-DAY/<platform>/composer.lock /tmp/audit/
  printf '{"name": "x/audit", "repositories": [{"type": "composer", "url": "https://packages.drupal.org/8"}]}\n' > /tmp/audit/composer.json
  cd /tmp/audit && composer audit --locked --no-plugins --no-scripts    # add --no-dev when require-dev was not installed
```

### Same-name respins: a changed lock replaces unless it adds advisories

A box fetches a catalogue platform only while its directory is absent, so a tarball
republished under the same name with a different lock reaches new installs and never
the boxes that already hold that platform.

A same-name tarball whose lock changed
replaces the published one unless it **adds advisories**: distribute audits both locks
against today's advisories, and the new one is refused when it carries an advisory the
published one lacks, or when either audit cannot finish or be compared. A lock that
clears advisories, or carries the same ones, replaces. Site owners who need a fix on a
platform already on their box rebuild their own platform in `~/static`.

`staticbuild distribute` enforces it for every Composer-built tarball: the
distributions on `distro/` and the vanilla `drupal-*` cores on `core/`. When the shelf
already holds a tarball of the same name, it compares the sha256 of the `composer.lock`
inside both, joined with that of a `patches.lock.json` beside it, so a respin whose
patch list moved under an unchanged lock still differs. A patch whose content changed
behind the same URL is not seen: varbase's `patches.lock.json` records no patch hashes,
so such a varbase respin passes as the same lock under new bytes.

A lock that adds
advisories, a lock missing on either side, or an audit that cannot finish or be
compared leaves the published tarball in place, logs both hashes and both advisory
counts, and marks the row `REFUSED`, with the `-O` command below the table; once the
other tarballs are published the run exits 3, a status of its own so a wrapper can
tell the guard working from a fatal error (exit 1). Failed builds are reported in their
rows and do not change the exit code. The same lock under new bytes, an ordinary re-tar,
passes.

A deliberate same-name rebuild names what it overwrites:
`staticbuild -O distribute <platform> ...` overwrites only those platforms' published
tarballs, logs both lock hashes, marks the row `OVERWRITTEN`, and warns that the
boxes which already fetched them keep the old bytes; any other changed tarball in the
day dir follows the rule above. `-O` without names, names without `-O`, a name not in
the day dir and `-O` with any other action are refused before anything is copied.

The
Backdrop, Grav and Textpattern tarballs carry no lock and are copied as before, as are
the dev-extension and contrib shelves. Every copy onto a shelf takes only a plain file
from the day dir (never a symlink or a FIFO) and replaces the destination rather than
writing through a symlink already there.

## What it builds (example run; versions are derived per build)

Distributions, published to `/var/www/static/distro`:

```sh
  commerce_kickstart-5.1.0-11.4.7
  drupal_cms_installer-2.1.6-11.4.7
  farm-4.0.6-11.3.17
  localgov-4.0.5-11.4.7
  openculturas-3.0.8-11.3.17
  openfed-13.6.7-10.6.17
  opigno_lms-3.2.7-10.6.17
  social-13.1.0-10.6.17
  thunder-8.4.4-11.4.7
  varbase-11.0.0-11.4.6
```

Raw cores, published to `/var/www/static/core`, latest patch of each supported minor:

```sh
  drupal-10.2.12    drupal-11.1.10
  drupal-10.3.14    drupal-11.2.14
  drupal-10.4.10    drupal-11.3.17
  drupal-10.5.12    drupal-11.4.7
  drupal-10.6.17
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

Five artefacts, always rebuilt at the latest upstream tag (pin any with the matching
`_*_TAG` in the config block):

- **backdrop** — Backdrop CMS core (`backdrop/backdrop`), from its latest GitHub
  release `backdrop.zip`. Repackaged versioned as `backdrop-<ver>.tar.gz` (extracts
  to `backdrop-<ver>/`), classified as a core and managed on the mirror exactly like
  the Drupal cores: every published version is retained, the resolved version is
  stamped to `backdrop.txt` (published only after its tarball, so the stamp never
  points at a missing file) — BOA names the platform from the stamp and fetches the
  matching tarball — and a version-less `backdrop.tar.gz` compat tarball of the newest
  release (extracting to `backdrop/`, the pre-versioning contract) is refreshed for
  already-deployed BOA releases.

  No contrib is baked into the versioned core
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
  `/var/www/static/dev/{dev,lts,pro}/contrib`. Unlike `bee` and the Drush extension it
  is consumed by a pinned version on the BOA side — after publishing a newer tag,
  bump the pin in `OCTOPUS.sh.txt` and `BOA.sh.txt` together (a newer publish is
  inert until then; `staticbuild check` surfaces the drift as the `bd-redis` row).
- **webform_backdrop** — the Backdrop webform contrib module (`backdrop-contrib/webform`),
  the first curated `o_contrib_backdrop` bundle member beyond the cache module (2026-09).
  Packaged versioned as `webform-<tag>.tar.gz` (the publish name drops the `_backdrop`
  suffix) wrapping a `webform/` directory, published to the per-tree contrib shelf
  `/var/www/static/dev/{dev,lts,pro}/contrib`. A plain bundle member — extracted into
  `o_contrib_backdrop` directly, no shared-store symlink, no cnf pin — fetched by the
  satellite side as a version literal: after publishing a newer tag, bump that literal
  in `lib/functions/satellite.sh.inc` (`_satellite_download_o_contrib_backdrop`), not in
  `OCTOPUS.sh.txt`/`BOA.sh.txt`; `staticbuild check` surfaces the drift as the
  `bd-webform` row.

## Grav family

staticbuild is also the Grav 2 builder. Like Backdrop it is not Composer-based
(no `/usr/bin/php` switch — just wget/unzip) and always fetches the newest
upstream release (pin with `_GRAV_TAG`). It is NOT part of `staticbuild all` —
build it with its own subcommand:

```sh
  staticbuild grav               # build + package + publish only the Grav family
```

Four artefacts, all published to `/var/www/static/core`:

- **grav-\<ver\>.tar.gz** — the official ADMIN BUNDLE release
  (`grav-admin-v<ver>.zip`: admin/login/form/email + api + admin2
  preinstalled), repackaged versioned (extracts to `grav-<ver>/`) for the
  platform build.
- **grav.tar.gz** — the version-less compat tarball of the newest release,
  built by a SEPARATE `tar --transform` invocation so it extracts to `grav/`
  (a copied archive would extract to the versioned name). It is the
  transitional fallback `_create_grav_basic_version` falls back to when a
  mirror carries no versioned Grav tarball yet.
- **grav-admin-v\<ver\>.zip** — the raw official zip kept verbatim as the
  per-site upgrade shelf: the upgrade engine feeds it to gpm direct-install as
  a LOCAL file, so `official_gpm_only` stays enforced and no box ever talks to
  getgrav.org.
- **grav.txt** — the version stamp, published LAST so a consumer can never
  resolve a version whose artefacts are not on the mirror yet.

## Textpattern family

staticbuild is also the Textpattern builder. No Composer, no php switch, and it
is NOT part of `staticbuild all` either — build it with its own subcommand:

```sh
  staticbuild txp                # build + package + publish only the Textpattern family
```

Built from the official GitHub release `.tar.gz` — never the `.zip`, which
ships no `/sites` scaffold (the always-multisite layout requires it; the build
asserts `/sites` is present before packaging). The release publishes a
`.SHA256SUM` beside each asset and the build verifies it before packaging.
Newest upstream release always; pin with `_TXP_TAG`. Three artefacts, all
published to `/var/www/static/core`:

- **textpattern-\<ver\>.tar.gz** — the versioned platform tarball (extracts to
  `textpattern-<ver>/`; the official tarball already uses that layout, so no
  rename is needed).
- **textpattern.tar.gz** — the version-less compat tarball of the newest
  release, built by a SEPARATE `tar --transform` invocation so it extracts to
  `textpattern/` (a copied archive would extract to the versioned name).
- **textpattern.txt** — the version stamp, published LAST. BOA resolves the
  platform version from this stamp at satellite-make time and fetches the
  matching versioned tarball, with the version-less tarball as the fallback.

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
farmos     # farm-4.0.6-11.3.17  (farmOS caps core at 11.3)
           # visit: https://github.com/farmOS/farmOS/releases
           # wget https://github.com/farmOS/farmOS/releases/download/4.0.6/farmOS-4.0.6.tar.gz
           # tar -xzf farmOS-4.0.6.tar.gz && mv farmOS farm-4.0.6-11.3.17
           # cd ~/static/MONTH-DAY/farm-4.0.6-11.3.17
           # composer config --no-plugins allow-plugins true
           # composer config --no-plugins --json policy.advisories.block false
           # composer update --no-install --no-scripts
           # composer install --no-dev
```

```sh
cms        # composer create-project drupal/cms drupal_cms_installer-2.1.6-11.4.7 --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/MONTH-DAY/drupal_cms_installer-2.1.6-11.4.7
           # composer config --no-plugins allow-plugins true
           # composer config --no-plugins --json policy.advisories.block false
           # composer update --no-install --no-scripts
           # composer install --no-dev
           # composer require drush/drush drupal/migrate_plus drupal/migrate_tools drupal/migrate_upgrade --no-scripts --no-interaction --update-no-dev   # post-update-cmd exits non-zero; cms dev-requires drush, non-interactive confirms the move to require; migration pipeline contribs absent upstream; --update-no-dev keeps require-dev out of the platform, as the builds ending in install --no-dev do
```

```sh
culturas   # composer create-project --remove-vcs drupal/openculturas_project openculturas-3.0.8-11.3.17 --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/MONTH-DAY/openculturas-3.0.8-11.3.17/
           # composer config --no-plugins allow-plugins true
           # composer config --no-plugins --json policy.advisories.block false
           # composer config --json extra.composer-patches.ignore-dependency-patches '["openculturas/openculturas-distribution"]'  # drop dependency patches (stale + composer-patches 2.x cannot apply to dist installs)
           # composer update --no-install --no-scripts
           # composer install --no-dev
           # curl -fsS -o /tmp/err.patch https://www.drupal.org/files/issues/2023-06-29/entity_reference_revisions-2799479-fix-only.patch
           # (cd web/modules/contrib/entity_reference_revisions && patch -p1 < /tmp/err.patch)  # LOAD-BEARING: shipped views need it or every page 500s
           # cd web/profiles/contrib/openculturas-distribution
           # mv profile openculturas
           # mv openculturas ../ && mv * ../ && cd ../ && rm -rf openculturas-distribution
           # cp ~/static/MONTH-DAY/farm-4.0.6-11.3.17/web/sites/example.sites.php ~/static/MONTH-DAY/openculturas-3.0.8-11.3.17/web/sites/
```

```sh
commerce   # composer create-project -s dev centarro/commerce-kickstart-project commerce_kickstart-5.1.0-11.4.7 --no-dev --no-interaction --no-install --no-scripts
           # name by centarro/commerce_kickstart (the profile, 5.1.0); the project template stays dev-only
           # cd ~/static/MONTH-DAY/commerce_kickstart-5.1.0-11.4.7
           # composer config --no-plugins allow-plugins true
           # composer config --no-plugins --json policy.advisories.block false   # commerce_kickstart blocks advisory-affected deps
           # composer install --no-dev
           # composer require centarro/certified-projects
           # composer update --no-install --no-scripts
           # composer install --no-dev
```

```sh
localgov   # composer create-project drupal/localgov_project:^4 localgov-4.0.5-11.4.7 --no-dev --no-interaction --no-install --no-scripts
           # name by drupal/localgov (the distribution, 4.0.5); localgov_project versions separately
           # cd ~/static/MONTH-DAY/localgov-4.0.5-11.4.7
           # composer config --no-plugins allow-plugins true
           # composer config --no-plugins --json policy.advisories.block false
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
           # composer create-project openfed/openfed-project:^13 openfed-13.6.7-10.6.17 --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/MONTH-DAY/openfed-13.6.7-10.6.17
           # composer config --no-plugins allow-plugins true
           # composer config --no-plugins --json policy.advisories.block false
           # composer install --no-dev                    # bootstrap; rc 4 EXPECTED, tolerated
           # composer update --no-install --no-scripts    # complete lock incl. include-file libraries
           # composer install --no-dev
           # The profile pins drupal/entity_browser exactly: 2.16 in 13.6.7, the release
           # that fixes SA-CONTRIB-2026-094.
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
           # composer create-project opigno/opigno-composer opigno_lms-3.2.7-10.6.17 --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/MONTH-DAY/opigno_lms-3.2.7-10.6.17
           # composer config --no-plugins allow-plugins true
           # composer config --no-plugins --json policy.advisories.block false
           # composer config --unset replace
           # composer require --no-update --no-scripts h5p/h5p-core:'1.27.*'
           # composer update --no-install --no-scripts
           # composer install --no-dev
           # composer require drush/drush --no-scripts --no-interaction --update-no-dev   # upstream keeps it in require-dev; non-interactive confirms the move to require; land the site-local Drush HERE, not at platform verify on every box
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
           # composer create-project goalgorilla/social_template:dev-master social-13.1.0-10.6.17 --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/MONTH-DAY/social-13.1.0-10.6.17
           # composer config --no-plugins allow-plugins true
           # composer config --no-plugins --json policy.advisories.block false
           # composer require --no-update --no-scripts goalgorilla/open_social:^13
           # composer update --no-install --no-scripts
           # composer install --no-dev
           # composer require drush/drush --no-scripts --no-interaction --update-no-dev   # the chassis ships none; land the site-local Drush HERE, not at platform verify on every box
           # name by goalgorilla/open_social read from the LOCK (13.1.0) - upstream's
           # 13.0.2 tag still declares version '13.0.1' inside social.info.yml
           # builds under php83: 13.1.0 requires php ^8.3 and SOC is capped at 8.3
           # docroot is html/ (not web/), and a fresh install's front page is bare
```

```sh
thunder    # composer create-project thunder/thunder-project thunder-8.4.4-11.4.7 --no-dev --no-interaction --no-install --no-scripts
           # name by thunder/thunder-distribution (8.4.4); thunder/thunder-project versions separately (5.0.0)
           # cd ~/static/MONTH-DAY/thunder-8.4.4-11.4.7
           # composer config --no-plugins allow-plugins true
           # composer config --no-plugins --json policy.advisories.block false
           # composer update --no-install --no-scripts
           # composer install --no-dev
```

```sh
varbase    # RE-ENABLED 2026-08-11: upstream fixed the template in July 2026 (core pinned
           # explicitly + committed lock), after a year of drift that made every fresh
           # build uninstallable. Builds the 11 line since 2026-09-10 (stable upstream
           # since 2026-09-08; web/ layout, the catalogue VBX web_dir moved with it);
           # the 10 line's last build stays on the mirror for existing platforms.
           # PINNED to the 11.0.7 template (2026-09-17): 11.0.8's lock moves canvas
           # 1.10.1 -> 1.11.0 and a fresh install on it drops canvas_page_template_component
           # from core.extension while its config stays -- every page 500s, clones fail
           # updatedb. Move the pin only after a rig proves install AND clone.
           # composer create-project Vardot/varbase-project:11.0.7 varbase-VERSION-CORE --no-dev --no-interaction --no-install --no-scripts
           # cd ~/static/MONTH-DAY/varbase-VERSION-CORE
           # composer config --no-plugins allow-plugins true
           # (NO composer update: varbase installs from upstream's shipped lock; a
           # re-resolve pulls a newer patches stack that aborts on their own core patch)
           # composer install --no-dev --ignore-platform-req=ext-pdo_pgsql
           # (the lock pins drupal/ai_provider_amazeeio 1.4.2, which declares ext-pdo_pgsql;
           # BOA's PHP has no PostgreSQL driver and the installer never enables the module)
           # name by vardot/varbase from the lock (the drupal.org release number)
           # docroot is web/ from the 11 line (docroot/ on 10); each recipes/ dir needs a
           # default/content subdir (the build creates them); builds under php84
```

Vanilla cores, latest patch of each supported minor (full install, add drush, audit):

```sh
vanilla    # for each minor 10.2 10.3 10.4 10.5 10.6 11.1 11.2 11.3 11.4:
           # composer create-project drupal/recommended-project:<minor>.* drupal-<version> --no-dev --no-interaction
           # cd drupal-<version> && composer require drush/drush
           # then audit the lock as under "By hand" above (never fatal)
           # built: 10.2.12 10.3.14 10.4.10 10.5.12 10.6.17 11.1.10 11.2.14 11.3.17 11.4.7
```

### Clean up artefacts before packaging

```sh
  cd ~/static/MONTH-DAY/
  rm -f  */*/modules/o_contrib*
  rm -rf */*/sites/all/drush
  rm -f  */*/sites/all/modules/*
  rm -f  */*/sites/sites.php
  rm -f  */*/local_drush_unlocked.pid
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
  for d in */ ; do case "${d%/}" in drupal-*|backdrop-[0-9]*) continue ;; esac ; rm -rf "${d%/}"/*/core/profiles/* ; done
  for d in */ ; do case "${d%/}" in drupal-*|backdrop-[0-9]*) continue ;; esac ; tar -czf "${d%/}.tar.gz" "${d%/}" ; done
```

### Publish the tarballs to the static mirror

```sh
  cp -a ~/static/MONTH-DAY/drupal-*.tar.gz            /var/www/static/core/
  cp -a ~/static/MONTH-DAY/*.tar.gz                   /var/www/static/distro/   # then remove the drupal-* copies from distro/
```

Before a same-name distribution tarball replaces one already in `distro/`, compare the
`composer.lock` inside both: a changed lock under an old name never reaches the boxes that
already hold that platform (see "Same-name respins" above; `staticbuild distribute`
refuses it when it adds advisories or cannot be checked for them, unless `-O`).

Raw cores (`drupal-*`) go to `core/`; the distributions go to `distro/`. The Backdrop, Grav
and Textpattern artefacts are `core/` shelf content too: their family targets publish them
there and `staticbuild distribute` routes any of their tarballs it finds in the day dir there
as well, never to `distro/`, which nothing reads for them.

## Add them all as platforms in Ægir

Use paths like `MONTH-DAY/drupal-11.4.7` and run tests for site install, clone and migration.

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
  `.git`, its FreeformPatcher needs per-patch config).

  One patch is load-bearing and is
  applied with GNU `patch` after the build instead, fail-closed: the shipped views
  reference `entity_reference_revisions` relationship handlers that only exist with the
  ERR issue-2799479 patch — without it every front page request throws
  `ViewsData->get()` InvalidArgumentException and the site serves 500s.
- **commerce** — commerce_kickstart enables Composer security-advisory blocking itself
  (current Composer also blocks by default), which refuses advisory-affected core/deps;
  every distro build that resolves turns it off (`policy.advisories.block false`; varbase
  installs from upstream's lock, which Composer does not filter) and the audit records
  what shipped instead (see "Advisories: audited, not blocked").
- **thunder** — `thunder/thunder-project` (the template) versions independently (e.g. 5.0.0)
  from the actual distribution `thunder/thunder-distribution` (e.g. 8.4.4); name by the latter.
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
