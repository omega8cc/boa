# Prebuilt Stack Packages

BOA can install its heavy stack components -- Modern and Legacy OpenSSL, ICU,
cURL, and every selected PHP version -- from prebuilt per-release `.deb`
packages published on the BOA mirrors, instead of compiling each of them from
sources on every box. A fresh PHP version lands in seconds instead of minutes;
a version pin bump upgrades the whole fleet without recompiling anything.
PHP extensions are still built on the fly on every box (they are cheap and
bound to the exact PHP build), and every package install is verified against
a `sha256` sidecar before it is unpacked.

## The Switch

```sh
_USE_PREBUILT_PKGS=YES|NO
```

in `/root/.barracuda.cnf` controls the behaviour:

- On **Devuan Daedalus** the default is `YES` -- packages are used whenever a
  matching one is published, on install and upgrade alike. Set
  `_USE_PREBUILT_PKGS=NO` explicitly to always compile from sources.
- On all other systems the default is `NO` until a complete package set for
  that release is published and propagated; the default then flips per
  release. An explicit value in `.barracuda.cnf` always wins.

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
the source path without any extra configuration.

## Reading the Log

Every component consumed from a package logs one line in the barracuda
report log:

```sh
INFO: <Component> <version> installed from prebuilt package
```

A component that fell back leaves a different trace depending on where it
fell back:

- `NOTE: Prebuilt <package> failed health check; building from sources` --
  the package installed but its post-install probe failed, and the source
  build took over for that component.
- No line at all -- the package (or its checksum sidecar) could not be
  fetched. This is deliberately indistinguishable from "not published": the
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
- A daily cron runs `barracuda up-<tree>` (a cheap no-op when nothing
  changed) followed by `stackbuild all` -- any pin bump is packaged within
  24 hours. Boxes upgrading inside that window fall back to source builds by
  design.

`stackbuild` verbs:

```sh
stackbuild check     # installed versions vs published packages
stackbuild package   # build the missing packages
stackbuild publish   # gzip + sha256 sidecars into the mirror tree
stackbuild sync      # cross-sync fresh packages to the peer active mirror
stackbuild all       # package missing + publish + sync
```

## Adding a Builder Mirror for a New Release

To bring up the next release's builder (for example Excalibur alongside
Daedalus):

1. Create the VM and install BOA on the target release the normal way
   (`boa in-lts public <fqdn> <email> o1`); on a Debian base the installer
   converts it via the matching `auto*` tool automatically.
2. Set `_USE_PREBUILT_PKGS=NO` explicitly in `/root/.barracuda.cnf` and
   select `php-max` so all PHP versions build.
3. Confirm the box serves (or will serve) the mirror `/dev/` tree; set
   `_PUB_DIR` in `stackbuild`'s configuration block if the auto-detection
   (keyed on the existing prebuilt packages under `/var/www`) does not apply
   yet on a fresh mirror.
4. Set `_PEER_MIRROR` on BOTH active builders so each pushes its release's
   fresh packages to the other -- both then hold the complete package tree.
   Passive mirrors keep syncing from the authoritative Daedalus mirror
   exactly as before.
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

## Verified Baseline

Fresh-install verification on Devuan Daedalus against the public mirrors
(2026-07-15): all seven packages of the initial set -- `boa-ssl-legacy`,
`boa-ssl3`, `boa-curl`, `boa-icu`, `boa-php83`, `boa-php84`, `boa-php85` --
consumed on a pure-public fresh install with zero health-check failures and
zero loader errors; the OpenSSL-to-cURL chain landed in about 5 seconds
where the source path compiled for roughly 11 minutes. The forced-SSL
upgrade leg was verified green the same day.
