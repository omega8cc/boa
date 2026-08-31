# ddev-boa: Local Development Against a BOA-Hosted Site

`ddev-boa` is a [DDEV](https://ddev.com) add-on that pulls a BOA-hosted Drupal site's
**database and user files** into a local DDEV project on a developer's own machine. It is
aimed at hosting clients and the agencies working on their sites: it lets an existing DDEV
project behave like the hosted site and sync from it, without a full local BOA install.

It is published for `ddev add-on get`:

```sh
ddev add-on get omega8cc/ddev-boa
```

This document explains, for BOA operators and support, how the add-on works against the
BOA limited shell, what it can and cannot do, and how to help a client who gets stuck.

## What it does

Three commands, all run from the developer's DDEV project:

- `ddev pull boa` — downloads the site's database (via `drush @alias sql-dump`) and its
  user files (via `rsync`), placing them where DDEV imports them. It never pulls or pushes
  code, and there is intentionally no `ddev push boa`.
- `ddev boa-aliases` — lists the site's Drush aliases so the developer can set the correct
  one.
- `ddev boa-config` — reads the site's own reported settings (`drush @alias status`) and
  writes a local DDEV config matching the site's **PHP version**, **Drupal version** and
  **docroot**. The database engine is only *reported*, as a commented opt-in line: DDEV's
  own database imports a BOA dump fine, so it is deliberately left unchanged.

## How it reaches the site: the limited shell

The add-on uses only the client's normal `oN.ftp` account and their existing SSH key — the
same key they use to connect for SFTP. It runs every remote step as a single command over
SSH, and each one is already permitted by the BOA limited shell:

- The `oN.ftp` login shell is `mysecureshell`; for members of the `lshellg` group its
  configuration delegates command execution to `lshell`, so `ssh oN.ftp@server "<command>"`
  reaches the jail.
- `lshell`'s `overssh` set is what governs non-interactive commands. It permits `drush`
  (and `drush8`/`drush10`/`drush11`), `mysql`/`mysqldump`/`mydumper`, `rsync` and `scp`,
  among others. It does **not** permit `tar`, `cat`, `vdrush` or a site-local
  `vendor/drush/drush/drush.php`, so the add-on never relies on those over SSH.
- The master and server Drush contexts (`@hostmaster`, `master_db`, `server_master`,
  `server_localhost`) are forbidden. The add-on only ever uses the site's own `@alias`.

## Drush version, deliberately

The database dump uses `drush @alias sql-dump` — that is, **Drush 8**, the only standalone
Drush that is integrated with Ægir site aliases. `sql-dump` reads the site's database
credentials straight from the alias, so it produces a correct dump for any Drupal version
(6 through 11+) without bootstrapping Drupal. Standalone `drush10`/`drush11` exist on BOA
only to convert alias names and return nothing useful for a dump; site-local `vdrush` is
the right tool for updates but is not reachable over a non-interactive SSH command. So the
add-on defaults to `drush` and documents `drush8` as the explicit synonym.

Locally, in DDEV, the developer uses **site-local** Drush with `--root`/`--uri` (simply
`ddev drush`), with no alias — the add-on's README shows this. Aliases are a server-side
Ægir concept and are not needed on the developer's machine.

## Files are pulled dereferenced

BOA's native files-symlinking makes a site's `files` directory a symlink into the
per-account store (`.../static/files/<site>/files`). The add-on pulls files with
`rsync -rLptz`, and `-L` (`--copy-links`) dereferences symlinks — including nested symlinks
that point into the store — so the developer receives **real files**, never dangling
symlinks pointing at `/data/disk/...` paths that do not exist on their machine. Only the
public `files` directory is pulled, not the separate `private` directory.

## Helping a client

- **`ddev boa-aliases` shows nothing / `ddev pull boa` cannot find the alias.** The site's
  aliases are mirrored into `/home/oN.ftp/.drush/` by `manage_ltd_users.sh` (cron), and
  only for registered, live sites. On a freshly provisioned site the mirror may not have
  run yet; it is populated within a few minutes. Confirm the site is verified and live.
- **Alias name looks wrong.** The Drush 8 alias (dotted, e.g. `@sub.example.com`) differs
  from the Drush 10/11 form (hyphens except the last extension, `@sub-example.com`). The
  add-on defaults to Drush 8, so the dotted form is correct. `ddev boa-aliases` prints the
  exact names.
- **"forbidden char/command over SSH".** The developer tried a command the limited shell
  does not allow over SSH (for example a raw `cat`, `tar`, or a site-local `vdrush`). The
  add-on itself only uses allowed commands; a hand-run command outside it may hit this.
- **No SSH identity.** `ddev pull boa` needs the key in the agent inside the web container:
  the developer runs `ddev auth ssh` first.
- **PHP version not detected by `ddev boa-config`.** The version is read from the site's
  active PHP path in `drush @alias status`; if it cannot be parsed the developer sets
  `php_version` manually and re-runs `ddev restart`.

## Scope

`ddev-boa` reproduces the runtime a site sees — its database, files, PHP version and
Drupal type — read from what BOA reports for the site; the database engine is reported
as a commented opt-in only, never switched. It does not reproduce the
BOA server itself: there is no Ægir/Hostmaster panel, no Octopus multi-tenancy, no CSF, and
DDEV's nginx/PHP are stock builds, not BOA's own compiled ones. Per-site `php.ini` tuning
and BOA's nginx directives are not exported (they are not readable through the limited
shell). For a full local BOA server, see *BOA Local* (a prebuilt VM image), a separate
effort.
