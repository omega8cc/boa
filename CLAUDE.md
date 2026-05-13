# CLAUDE.md — boa-private

> Extends ~/.claude/CLAUDE.md. Global conventions apply throughout.

## Project purpose

Primary working repository for BOA (Barracuda/Octopus/Aegir) stack development.
BOA is a full-featured Drupal hosting stack built on Aegir, Nginx, Percona MySQL,
and a large collection of bash scripts and libraries. This private repo mirrors the
structure of the public BOA repo with additional working branches, internal notes,
and in-progress changes not yet ready for public exposure.

This repo is the entry point for: boa-control-refactor, boa-modernisation, and
boa-features workstreams. Each runs on its own branch within this repo.

## Scope boundaries

**In scope:**
- All BOA bash scripts under aegir/, barracuda/, octopus/, and lib/ directories
- Nginx configuration templates
- BOA control file logic and INI configuration handling
- Upgrade and install path logic in daily.sh, barracuda.sh, octopus.sh
- Any new features or improvements on the boa-features workstream

**Out of scope:**
- Aegir Hostmaster Drupal codebase (separate fork repo under omega8cc)
- Provision backend (separate fork repo under omega8cc)
- Drush (separate fork repo under omega8cc)
- Any file fetched from mirrors at runtime — edit the fetch logic, not the fetched artifact
- Any commit or push to the public BOA repo — Claude Code works on `private-dev` only;
  surfacing work to the public repo is Adam's responsibility

## Repository layout

```
boa-private/
  CLAUDE.md
  DECISIONS.md
  CHANGELOG.md
  deps/
    manifest.yml       — all fork coordinates and pins
  aegir/               — Aegir-related BOA scripts
  barracuda/           — Barracuda installer and upgrade scripts
  octopus/             — Octopus platform manager scripts
  lib/                 — shared bash libraries and includes
  nginx/               — Nginx config templates
  conf/                — BOA control file templates and INI schemas
  docs/                — internal working notes (not the public docs project)
```

## BOA architecture reminder

BOA install and upgrade fetches most dependencies at runtime:
- Devuan/Debian packages via apt
- Source tarballs from our own mirrors (not upstream directly)
- Fork repos via git clone at defined pins

Before modifying any fetch URL, mirror reference, or version pin, consult
deps/manifest.yml and flag the change for Tier 3 testing in boa-testing.
A wrong pin or broken mirror URL causes a failed install with no fast recovery path.

## Key files — handle with care

- `barracuda/barracuda.sh` — main installer, extremely long, spaghetti sections exist,
  do not refactor without a DECISIONS.md entry and Tier 3 test coverage
- `octopus/octopus.sh` — platform manager, similarly complex
- `lib/daily.sh` — daily maintenance runner, contains INI migration conversion logic;
  the INI conversion code must not be removed until boa-control-refactor is complete
- `conf/*.cnf` — control file templates; changes here affect all installs

## Branch model

This repo has one active branch for Claude Code: `private-dev`.

All work — including boa-control-refactor, boa-modernisation, and boa-features
workstreams — is done on `private-dev`. Logical separation between workstreams
is maintained through clear commit messages, CHANGELOG.md sections, and
DECISIONS.md entries, not through separate branches.

Public BOA branches (`5.x-dev`, `5.x-dev-base`, `5.x-pro`, `5.x-lts`, etc.)
exist on the public remote only. Claude Code never checks out or commits to them.
See global CLAUDE.md for the full public branch naming scheme and the warning
about BOA SKYNET auto-update triggered by tags.

## Environment

- Target OS: Devuan Daedalus (primary), Debian Bookworm (secondary/legacy)
- Runs as: root (BOA requires root throughout)
- Key paths:
  - `/root/.barracuda.cnf` — main Barracuda control file
  - `/root/.o1.octopus.cnf` — default Octopus Aegir control file
  - `/data/disk/o1/` — default Octopus Aegir instance root
  - `/var/aegir/` — Aegir Master Instance home
  - `/etc/nginx/` — Nginx config root
  - `/opt/local/bin/` — BOA helper binaries
- Devuan detection: check `/etc/devuan_version` before any OS-specific branch

## Known constraints and gotchas

- BOA has no test suite. All validation is via boa-testing project (separate).
- Many scripts source each other via relative paths — do not move files without
  tracing all source/include references first.
- `daily.sh` runs as a cron job; changes must be idempotent and safe to interrupt.
- Legacy Perl-origin logic exists in some lib files — treat as read-only unless
  the modernisation workstream explicitly targets it.
- Nginx reload (not restart) is the safe operation during live traffic.
- Never `killall php-fpm` or `service mysql restart` in scripts without a safety
  check for active connections.
- Percona 8.4 soname: `libperconaserverclient24` — legacy servers may still have
  `libperconaserverclient22`, handle both in any script that links against it.
- `mydumper` is used for dump/restore — compatible with Percona 5.7 and 8.4.

## Testing approach

- Tier 1 (every commit): shellcheck on all modified bash files, php -l on any PHP
- Tier 2 (targeted): deploy to persistent dev BOA VM, exercise affected subsystem
- Tier 3 (full install): via boa-testing project, required for: installer changes,
  upgrade path changes, mirror/fetch changes, anything touching bootstrapping

## Definition of done

- shellcheck clean (no errors, warnings reviewed and suppressed with comment if intentional)
- CHANGELOG.md updated on `private-dev`
- DECISIONS.md updated if architecture changed
- Committed and pushed to `omm` (`private-dev` branch only)
- PR description prepared for Adam to review before any public merge
- Tier 2 or Tier 3 test completed as appropriate, result noted in PR

## References

- Public BOA repo: https://github.com/omega8cc/boa
- Aegir project: https://www.aegirproject.org
- BOA control file reference: (boa-docs project, in progress)
