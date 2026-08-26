# Prebuilt Stack Packages

BOA can install its heavy stack components -- Modern and Legacy OpenSSL, ICU,
cURL, Valkey, Nginx, Unbound, Pure-FTPd, and every selected PHP version -- from prebuilt
per-release `.deb` packages published on the BOA mirrors, instead of compiling
each of them from sources on every box. A fresh PHP version lands in seconds
instead of minutes; a version pin bump upgrades the whole fleet without
recompiling anything.
PHP extensions are still built on the fly on every box (they are cheap and
bound to the exact PHP build), and every package install is verified against
a `sha256` sidecar before it is unpacked.

## The Switch

```sh
_USE_PREBUILT_PKGS=YES|NO
```

in `/root/.barracuda.cnf` controls the behaviour:

- On **Devuan Daedalus** and **Devuan Excalibur** the default is `YES` --
  packages are used whenever a matching one is published, on install and
  upgrade alike (Excalibur since 2026-07-20, when its complete boa-* set
  went live on the mirrors). Set `_USE_PREBUILT_PKGS=NO` explicitly to
  always compile from sources.
- On all other systems the default is `NO` until a complete package set for
  that release is published and propagated; the default then flips per
  release. An explicit value in `.barracuda.cnf` always wins. Builder boxes
  keep an explicit `NO` -- see the builder requirements below.

The switch never changes *whether* a component is (re)built -- all existing
version checks, force flags, and self-heal logic stay exactly as they were.
It only replaces the compile step with a package install when possible.

## Automatic Fallback

Any failure on the package path -- no package published for your release or
version, a checksum mismatch, a `dpkg` error, or a failed post-install health
check -- automatically falls back to the untouched source build for that one
component, with a single `NOTE:` line in the log. An unpublished component is
therefore the normal per-component opt-out: no package on the mirror simply
means that component keeps compiling from sources.

Boxes with a custom build shape (a non-empty `_PHP_EXTRA_CONF`, or a pinned
`_ICU_FORCE_VRN`) are refused the PHP packages automatically, because the
published packages are built with shipped defaults only -- such boxes keep
the source path without any extra configuration. The same shipped-defaults
rule gates the other components: a custom Nginx module set keeps the source
path, Valkey packages exist for major 9 only, and the Unbound and Pure-FTPd
packages are refused on a box without the Modern OpenSSL tree their binaries
link against. The Nginx and PHP packages are additionally verified against
the compiled-in OpenSSL (and, for PHP 8.1+, ICU) versions the box currently
expects -- the same tokens the next run's rebuild decision reads -- so a
stale package published before a pin bump is refused and purged, and that
component builds from sources instead of silently installing binaries built
against the previous library. The Pure-FTPd package carries the ten `/usr/local` binaries
only; the TLS certificate, DH parameters, PAM and configuration files stay
box-generated or installer-managed on both paths.

## Reading the Log

Every component consumed from a package logs one line in the barracuda
report log:

```sh
INFO: <Component> <version> installed from prebuilt package
```

A component that fell back leaves a different trace depending on where it
fell back:

- A `NOTE:` line naming the reason -- a failed package download, a checksum
  mismatch, a `dpkg` error, or a failed post-install health check each log
  one `NOTE: ... falling back to sources` / `... building from sources`
  line before the source build takes over for that component.
- No line at all -- the checksum sidecar probe found nothing to fetch.
  This is deliberately indistinguishable from "not published": the
  component compiles from sources silently, exactly as on a mirror that
  never carried it.

To audit what a run actually consumed, grep the report log for
`installed from prebuilt package` -- never conclude from the absence of
fallback NOTEs alone.

## Builder Mirrors

Packages are produced by the `stackbuild` tool on dedicated builder mirror
VMs -- one per supported release. The builder never re-implements any build
logic: it runs after a real `barracuda up-<tree>` on a real BOA box of the
target release, and only snapshots, packages, and publishes what the
unmodified installer built. The version pins in the installer remain the
single source of truth, and the builder doubles as a standing upgrade canary
ahead of the fleet.

Builder box invariants:

- `_USE_PREBUILT_PKGS=NO` is set explicitly and permanently in
  `/root/.barracuda.cnf` -- a builder must always compile from sources, or it
  would install its own packages and repackage them in a circle. `stackbuild`
  refuses to run otherwise.
- The builder cnf selects the full PHP matrix (`php-max`), with all
  build-shape toggles at shipped defaults, so packages match the default
  build shape.
- `_XTRAS_LIST` in the builder cnf carries `FTP` (hosted builders converge
  it automatically). Pure-FTPd is the only packaged component gated on an
  xtra rather than installed unconditionally, and stackbuild can only
  package what the real upgrade installed -- a builder without the FTP
  xtra never publishes `boa-pure-ftpd`, and the fleet then source-builds
  it silently forever (an unpublished component is the by-design silent
  opt-out).
- A daily cron runs `barracuda up-<tree>` (a cheap no-op when nothing
  changed) followed by `stackbuild all` -- any pin bump is packaged within
  24 hours, including the packages a companion bump invalidates: when an
  OpenSSL pin bump makes the upgrade rebuild PHP and Nginx without changing
  their own versions, `stackbuild all` detects the rebuilt trees (newer than
  their published packages) and republishes them under the same filenames.
  Boxes upgrading inside that window fall back to source builds by design.

`stackbuild` verbs:

```sh
stackbuild check     # installed versions vs published packages
stackbuild package   # build the missing or stale packages
stackbuild publish   # gzip + sha256 sidecars into the mirror tree
stackbuild sync      # cross-sync fresh packages to the peer active mirror
stackbuild all       # package missing + stale + publish + sync
stackbuild force     # rebuild + republish regardless of published state
```

A published package counts as stale when the real upgrade rebuilt its
installed tree after the package was published -- the tool compares the
component's probe binary against the published file instead of
re-implementing any of the installer's rebuild triggers. Components the
upgrade does not rebuild on a companion bump (the dynamically linked Unbound
and cURL simply follow the upgraded library in place) correctly stay
untouched.

## Adding a Builder Mirror for a New Release

To bring up the next release's builder (for example Excalibur alongside
Daedalus):

1. Create the VM and install BOA on the target release the normal way
   (`boa in-lts public <fqdn> <email> o1`); on a Debian base the installer
   converts it via the matching `auto*` tool automatically.
2. Set `_USE_PREBUILT_PKGS=NO` explicitly in `/root/.barracuda.cnf`,
   select `php-max` so all PHP versions build, and make sure `_XTRAS_LIST`
   carries `FTP` so the xtra-gated `boa-pure-ftpd` gets built too.
3. Create `/root/.stackbuild.cnf` (an empty file is enough): its presence
   is what marks a build box -- the serial-gated fetch in `_update_agents`
   deploys `stackbuild` (and `staticbuild`) to `/opt/local/bin/` only on
   boxes carrying it. Confirm the box serves (or will serve) the mirror
   `/dev/` tree; set `_PUB_DIR` in the cnf if the auto-detection (keyed on
   the existing prebuilt packages under `/var/www`) does not apply yet on a
   fresh mirror.
4. Set `_PEER_MIRROR` in `/root/.stackbuild.cnf` on BOTH active builders so
   each pushes its release's fresh packages to the other -- both then hold
   the complete package tree. Never set it by editing the script: deployed
   copies are refreshed by the serial-gated fetch on every barracuda run,
   which resets in-script edits (a build with it unset publishes only
   locally and warns). Passive mirrors keep syncing from the authoritative
   mirror exactly as before.
5. Add the daily cron: `barracuda up-<tree>` then `stackbuild all`.
6. Only after the new release's package set is published and propagated,
   the shipped default for that release flips to `YES` in a BOA update --
   never flip it before the packages exist.

## Integrity and Naming

Every package is published as
`boa-<component>_<version>.<codename>_amd64.deb.gz` with a
`.deb.gz.sha256` sidecar hashing the compressed file. The installer fetches
the sidecar first, verifies the checksum before unpacking anything, and
constructs the filename from its own version pins -- so mirrors safely hold
many versions side by side and old packages are never deleted on publish.

Package dependencies carry distro libraries only, resolved on the builder for
its exact release. The BOA-to-BOA ordering (PHP needs the BOA OpenSSL, ICU,
and cURL trees) is enforced by the installer itself, so a box whose companion
component fell back to a source build keeps working without any dpkg-level
coupling.

## Archived Legacy Database Packages

Distinct from the `_USE_PREBUILT_PKGS` stack packages above -- a separate
mechanism with its own trigger and no switch. Percona Server 5.7 is EOL
upstream: its apt suite is frozen but still served, and a fresh
Daedalus/bookworm install that defaults to `_DB_SERIES=5.7` normally takes it
straight from `repo.percona.com`. This is insurance for the day that stops
being true -- and for any local reason apt delivers nothing (network, DNS,
keyring), since the symptom is the same either way: "no installation
candidate" from apt and, because that error is silent, a box that hangs
forever waiting for a MySQLD that never installs. BOA therefore archives
the frozen 5.7 debs -- `percona-server-common-5.7`, `libperconaserverclient20`,
`libperconaserverclient20-dev`, `percona-server-client-5.7`,
`percona-server-server-5.7` -- on its own static `/dev/` mirror, each as a
`.deb.gz` with a `.sha256` sidecar hashing the compressed file, exactly like
the stack packages.

The recovery is automatic and needs no configuration. When the apt path does
not deliver `percona-server-server-5.7` on a fresh 5.7/bookworm box, BOA fetches
the five archived debs from the mirror, verifies each checksum before unpacking,
installs them with `dpkg -i`, and pulls the distro-lib dependencies
(`libaio1`, `libdbi-perl` ...) from the OS repos with `apt-get install -f` --
these are ordinary distro packages, so whatever kept the Percona path from
delivering does not affect them. It is idempotent: an upgrade run on a box with a working 5.7 already
installed never triggers it, and it only ever runs for the 5.7/bookworm Percona
path -- the 8.x and Excalibur paths are untouched. If both the apt path and the
mirror fallback fail to install a database server, the install now aborts
immediately with a clear `FATAL ERROR:` naming both failures, instead of
wedging in the MySQLD wait loop.

## Verified Baseline

Fresh-install verification on Devuan Daedalus against the public mirrors
(2026-07-15): all seven packages of the initial set -- `boa-ssl-legacy`,
`boa-ssl3`, `boa-curl`, `boa-icu`, `boa-php83`, `boa-php84`, `boa-php85` --
consumed on a pure-public fresh install with zero health-check failures and
zero loader errors; the OpenSSL-to-cURL chain landed in about 5 seconds
where the source path compiled for roughly 11 minutes. The forced-SSL
upgrade leg was verified green the same day.
