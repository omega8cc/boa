# Migrating vanilla Ægir estates into BOA (aegir2boa)

How to adopt a **vanilla Ægir 3.x estate** (Apache or Nginx, `/var/aegir`,
single `aegir` user) into a **BOA Octopus account** on a separate BOA box,
with a drilled, per-site revert at every step until final DNS cutover.

This is NOT the BOA-to-BOA migration path — for moving an existing Octopus
instance between BOA boxes use `xoct` (see `MIGRATE-XOCT.md`). The aegir2boa
toolset exists because a vanilla source has none of the control files,
agents, or conventions xoct relies on, and because converting a vanilla box
to BOA in place has no cheap revert. The safe shape is the one xoct already
uses: migrate REMOTELY to a separate BOA target, then demote the old box to
an HTTP(S) proxy whose per-site revert is a file move.

The migration has three stages plus a read-only discovery phase:

```
stage 0   aegir2boa-preflight   read-only discovery; PASS/WARN/FAIL per stage
stage 1   aegir2boa-stage1      in-place Apache -> Nginx flip on the source
stage 2   aegir2boa-stage2      remote adoption into BOA + proxy window
stage 3   (manual runbook)      final DNS cutover + source decommission
```

Stage 1 exists because the whole stage-2 source-side machinery (vhost swap,
503 pause, proxy templates) is nginx-vhost-based; vanilla Ægir supports
Nginx natively, and the stage-1 revert is cheap (flip back to Apache — both
stacks stay installed until sign-off).

## The toolset

| Tool | Runs on | Role |
|---|---|---|
| `aegir2boa-preflight` | source (vanilla) | read-only discovery + stage gates |
| `aegir2boa-stage1` | source (vanilla) | Apache→Nginx flip, revert, status |
| `aegir2boa-stage2` | BOTH boxes | the migrator; dual-resident, verbs validate box class |

All three ship in the BOA tools distribution at `aegir/tools/bin/` but are
deliberately **not registered for fleet fetch** — no BOA box downloads or
runs them by itself, and they never self-update. Download them directly; the
source box needs no BOA installation, no account and no credentials to do it:

```bash
cd /usr/local/bin
for t in aegir2boa-preflight aegir2boa-stage1 aegir2boa-stage2; do
  wget https://files.boa.io/versions/dev/boa/aegir/tools/bin/$t
  chmod 755 $t
done
```

The path names the tree this copy of the documentation belongs to; the three
trees carry the same tools, so take them from the tree your target server
runs. **Use the short tree token** — a path such as `versions/5.x-lts/...`
returns an HTTP 200 "Under Construction" placeholder rather than a 404, so a
typo yields a file that looks downloaded and is not a script. Check what you
got: `head -1` must read `#!/bin/bash`.

Run them as root. `aegir2boa-stage2` is dual-resident: put the SAME script on
the source and the target; source verbs refuse to run on a BOA box and target
verbs refuse to run on a vanilla box.

Old-stack tolerance: the source-side tools assume nothing modern — bash
3.2/4.1-era and PHP 5.3-era safe; nothing executed on the source assumes
BOA. Target verbs assume a healthy BOA box.

Source OS: a Debian-family box — Debian, Ubuntu or Devuan. Vanilla Ægir 3
itself shipped one joint apt suite for Debian AND Ubuntu, and most legacy
estates ran Ubuntu, so both families are first-class sources. Nothing in
the tools branches on the distro name: everything the families share
(apt/dpkg, the `apache2` layout, `www-data`) is used as-is, and everywhere
their ERAS or install routes genuinely diverge — init system
(systemd/sysvinit/upstart), where the apache include lives (2.4
conf-available behind a2enconf, the deb postinst's bare conf-enabled
symlink, 2.2 conf.d), distro nginx and OpenSSH floors, the DB flavour
(Ubuntu 20.04+ ships MySQL 8.0 where Debian ships MariaDB) — the tools
probe the box at runtime, and `check` gates DB-generation parity against
the target. A non-apt (RPM-family) source is refused cleanly at stage 1
(its preflight requires `apt-get`); there is no path for it.

## Validation status — read before using on a client box

Proven end-to-end on disposable VMs (2026-07): both stage-2 routes, every
revert path (single-site, full two-box, target reset, db-import undo,
resume), stage-1 flip/revert/re-flip, and public serving through the proxy
window. That drill estate was Drupal-7-only and HTTP-only. The OS axis:
Debian 11 (bullseye) sources for every drill through 2026-08-12, and an
Ubuntu source drilled end to end on 2026-08-13 (jammy + PPA PHP 7.4 +
distro MySQL 8.0, on the deb-installed apache include layout) — stage-1
flip/revert/re-flip, the `check` DB-generation refusal live against two
Percona 5.7 boxes, and full per-site adoption of the MySQL 8.0 estate
into a Percona 8.4 target, proxy window and reverts included.

Re-validated in full on 2026-08-11 against a fresh vanilla source and a
fresh BOA target, on published tool bytes, with an estate carrying real
Let's Encrypt sites and a Drupal 9 composer platform. That re-validation
changed tool behaviour — including the new `peer` verb — so use current
published tool bytes: earlier copies do not carry the stage-1 HTTPS flip,
composer-platform adoption, `peer`, the HTTPS proxy window itself (an
earlier https proxy template emitted an HTTP/2 directive a distro nginx
rejects, so every HTTPS site failed `nginx -t` and refused to cut over
while HTTP sites proxied fine), or site-profile carry-over (2026-08-12) —
without which any site whose install profile is not `standard` fails its
import, every Drupal 6 site included. What the 2026-08-11 re-run settled:

- **Stage 1 on an encrypted estate is drilled**, not theoretical: flip,
  revert and re-flip on an `apache_ssl` estate with both HTTPS sites
  answering 200 on their own certificates at every step.
- **D8+ composer platforms are adopted as projects**, not as their docroots.
  Before the fix the platform was named after its `web/` directory (so any two
  collided) and `vendor/` never travelled, which no adopted site can survive.
  A Drupal 9 site now imports and serves on the target.
- **Every stage-2 revert path is re-drilled on that same HTTPS+composer
  estate** (it had only ever been drilled on the D7/HTTP-only July estate):
  single-site revert with its stale-dump refusal, full two-box revert
  (`revert --all` + `resume` + target `--reset-sites`), and the
  retry-needs-fresh-export path taken all the way back — the reverted estate
  was re-exported, re-adopted over its already-registered panel nodes (a path
  the first adoption never exercises) and re-proxied to the serving state.
  The db-import refusal is also verified as a refusal, not assumed:
  `check --route db-import` dies naming the non-D7 platform on a mixed
  estate.

Extended on 2026-08-12 with the family member both earlier drills lacked: a
mixed **Drupal 6 + 7** estate (Drupal 6 on d6lts 6.60), adopted per-site
into a NEW account on a php-max target. What that drill settled:

- **D6 adoption works end to end**: each D6 site registered with its own
  install profile — the drill found the import dropping the profile
  entirely, so ANY site on a non-`standard` profile failed, D6's `default`
  merely first to hit it — mapped to the target's PHP 5.6 pool via
  `multi-fpm.info`, its pool socket verified live in the nginx config
  (`$user_socket` → the account's `.56.fpm.socket`), adopted, proxied,
  publicly served through the window, and reverted: single-site with the
  stale-dump refusal, then the full two-box revert.
- **The db-import triad refuses a D6 platform** exactly as it refuses a
  D8+ one — verified as a refusal on this estate.
- **A reverted db-import no longer strands the estate's vhosts.** The
  drill caught `--revert-db-import` leaving vhost files the restored panel
  no longer owns; a later re-adoption of the same names then loses the
  server_name conflict to the DEAD vhost by include order and serves 500s
  while looking healthy. The revert now removes exactly the manifest URIs'
  vhosts and reloads nginx. The preflight also resolves a D6 platform's
  core version now (it previously read only D7's `bootstrap.inc` location
  and graded D6 as `?`).

Re-run in full on **2026-08-25** as an OS × Percona matrix on published
tool bytes (record: boa-testing `tier3/results/A2B-MX-2026-08-25.md`), the
first complete suite after ~130 commits to the toolset and the tree: the
Debian 11 estate (MariaDB 10.5; mixed D6 + D7 with two real-LE HTTPS sites
and a D9 composer platform, seven sites) adopted per-site into a Percona 5.7
target AND into a Percona 8.4 target; the Ubuntu 22.04 estate (PPA PHP 7.4,
distro MySQL 8.0, four D7 sites, two on LE) adopted into a Percona 8.4
target per-site AND by db-import (12-step import, identity surgery
asserted, full two-box revert with the orphan-vhost cleanup), and refused
by `check` against a Percona 5.7 target exactly as the DB-parity gate
promises (exit 1, `DB_PARITY=REFUSED`, route blanked); both stage-1 flips
green on both include layouts (a2enconf and the deb bare symlink), every
site's HTTP and HTTPS response matching its baseline at every transition.
The matrix found the one cell no earlier drill had visited, **D6 on a
Percona 8.4 target**: site users were minted `caching_sha2_password` and
PHP 5.6's mysqli aborts at the greeting, so both D6 sites served 503 while
the pre-fix import counted them adopted (exit 0; only the proxy gate
refused). Fixed the same day (aegir2boa 31723df = boa-private eff026d22):
D6 users pinned native at DB land, a serve-probe equality gate, exit-code
honesty; re-verified on the republished bytes (stage2 md5 1ae65afc) with a
fresh pair — db-import on 8.4 green, and the D6 per-site leg both ways: the
stock `authentication_policy` target FAILS the site loudly with the users
verifiably pinned, and the my.cnf remedy applied verbatim flips both D6
sites to 200 with the re-import landing clean. The server-side half is the
*Prerequisites* bullet on native auth; BOA sets it on Percona 8.4 (D-015).

Which leaves, honestly:

- **The HTTPS story is drilled end to end, and its certificate step is
  manual.** 2026-08-11: all five sites of an ssl-bearing estate served
  publicly through the source-side proxy with DNS still pointing at the old
  box, both encrypted ones presenting their own real certificates. Later the
  same day the full certificate loop closed: Encryption enabled per site on
  the target, real LE certificates issued THROUGH the proxy window (the
  bare-name ACME challenge validated via the proxy; the default `www.` SAN
  required the proxy-vhost www alias fix first), and
  `cert-sync --live` mirrored both target-issued certificates back to the
  proxy edge — `2 refreshed`, exit 0, the proxy thereafter serving the
  TARGET's certificates, serial-verified. What remains manual is the enable
  itself: adopted sites arrive with Encryption off, so the target holds no
  certificate until you enable it there (see cert-sync).
- **The db-import route is re-drilled end to end** (2026-08-11, on current
  published tool bytes): a fresh homogeneous-D7 estate — four sites, two on
  real Let's Encrypt HTTPS — flipped, adopted via the whole-DB import with
  its identity surgery and inline verify ladder (all four sites serving
  their baselines), proxied, and then fully reverted on both boxes
  (`--revert-db-import` restored the pre-import panel exactly; the source
  served locally again, HTTPS included). Its refusal on ineligible estates
  is verified as a refusal too. One route nuance stands (see cert-sync):
  db-import keeps vanilla's alias settings, so enabling Encryption there
  needs the `www.` alias added or a bare-name certificate requested.
- **A target without a php56 pool is not drilled.** D6 adoption is
  validated against a php-max target; the refusal ladder for a missing
  pool — `check` flagging the site, and the import's per-site FAIL when
  the socket never appears (a FAIL by design, not a warning: D6 cannot
  serve on the account default PHP) — exists in code but has not been
  exercised on a pool-less target.
- **Pre-3.x Ægir sources are refused** by the preflight floor — recognised
  and named, never mangled. There is no supported path for them yet.
- **Panel-domain continuity is not implemented.** The adopted panel lives
  at `<oN>.<target-fqdn>`; the old panel URL goes dark (503) at proxy
  time. Communicate the new URL to the client.
- **The upstart-era and apache 2.2 Ubuntu/Debian populations are
  feature-detected but undrilled.** The Ubuntu axis itself is drilled
  (2026-08-13: jammy source, MySQL 8.0, deb-installed include layout,
  full adoption + reverts — record: boa-testing
  tier3/results/A2B-UBUNTU-2026-08-13.md), and the tools are
  OS-agnostic by construction (same-day audit: no distro gate
  anywhere). What no cloud image exists to drill is the oldest era:
  upstart init (Ubuntu 12.04/14.04) and apache 2.2 (Debian 7 /
  Ubuntu 12.04) go through code paths that are reviewed and
  unit-verified only — treat a real estate of that era with the usual
  dry-run care and expect to read the dry-run output closely.

## Safety model (all acting verbs, all stages)

> **Every acting verb is a DRY RUN by default.** Append `--live` to act.
> `--live` is accepted only after a CLEAN dry run of the same verb and
> scope on the same box, and it **consumes** that clean token on entry —
> one dry run arms exactly one live run, and any failed live run forces a
> fresh dry run against the changed box before you can retry.
>
> **The serving path is never cut before its replacement is functionally
> proven.** The stage-1 flip probes real PHP through nginx+FPM on a
> scratch port while Apache still serves; the stage-2 proxy swap refuses
> any site the target does not already answer for; every nginx change is
> `nginx -t`-gated with automatic restore on failure. Every pre-handover
> failure is therefore a no-outage abort.
>
> Frontend tasks are polled by **latest vid only** (finished Ægir tasks
> retain stale status rows), and the tools never force-run the task queue.
> One scoped exception: when a task the tool ITSELF queued still sits at
> queued status after a minute, the tool runs that account's own
> dispatcher for it, once a minute, logging the drain — nothing else
> dispatches a freshly created account's queue during the adoption
> window, so polling alone would deadlock to the timeout and count the
> site a failure.

Every verb is idempotent behind marker files and safe to re-run. The
preflight and the stage-2 tool take a coarse per-scope lock against
concurrent runs; stage 1's guard is its consumed dry-run token (no
separate lockfile). Logs:
`/var/log/aegir2boa-stage1.log` and `/var/log/aegir2boa-stage2.log` (both
fall back to `/tmp` if `/var/log` is not writable) — the first place to
look on any failure.

## Prerequisites

- **A Debian-family source box** — Debian, Ubuntu or Devuan, with working
  apt/dpkg sources and the Debian `apache2` layout. Any era the estate
  survived on: the tools feature-detect the differences that matter (init
  system, where the apache include lives, distro nginx and OpenSSH
  floors, DB flavour — a MySQL 8.0 source needs a current-generation
  target and `check` gates exactly that). An EOL release whose mirrors
  moved (archive.debian.org / old-releases.ubuntu.com) must have its apt
  sources pointed there first — stage 1 installs nginx and php-fpm from
  the box's own repositories.
- **Arrange reachability with `peer` rather than by hand.** The target's lfd
  reads an `ssh-keyscan` / first-contact burst as abuse and temp-blocks port
  22 — proven the hard way — so the firewall must be opened before the key
  ever travels. The verb does both halves in the right order:

```sh
  # ON THE SOURCE: mint a dedicated key and print the target-side command
  aegir2boa-stage2 peer --target <target-ip>                     # dry
  aegir2boa-stage2 peer --target <target-ip> --live

  # ON THE TARGET: open csf.allow AND csf.ignore, clear any tripped block,
  # reload csf, authorise the key (the command printed above supplies it)
  aegir2boa-stage2 peer --source <source-ip> --pubkey-file <f>   # dry
  aegir2boa-stage2 peer --source <source-ip> --pubkey-file <f> --live

  # ON THE SOURCE again: confirms it can reach root@target
  aegir2boa-stage2 peer --target <target-ip> --live
```

  Both halves are idempotent. The key carries an `a2b-` comment so it is easy
  to revoke at decommission. `check` verifies BatchMode ssh works.
- **A fresh preflight report on the source.** The report lands under
  `/tmp`, which is tmpfs on many boxes — a reboot eats it, and `check`
  refuses a report from a different host. Re-run the preflight after any
  reboot AND after the stage-1 flip: `check` reads the http service type
  from the newest report, and a report taken before the flip still says
  apache. Copy the `.txt`/`.env` pair somewhere durable for the record.
- **Stage 1 signed off**: the source serves the whole estate on Nginx.
- **Target PHP pools** for the estate's needs (a D6 site needs a php56
  pool on the target; `check` grades this per site).
- **D6 on an 8.0+/8.4 target additionally needs the server to ADVERTISE
  `mysql_native_password`.** PHP 5.6's mysqli dies at the handshake
  greeting when the server's default first-factor is
  `caching_sha2_password` — before the user's own plugin is even
  consulted — so a D6 site bootstraps in CLI yet serves its own
  "Site off-line" 503 on the web. The import pins each D6 site's DB
  user to `mysql_native_password` (and refuses, loudly, when the plugin
  is disabled), but the server-side default must also be native:
  `authentication_policy = mysql_native_password,,` in my.cnf, and on 8.0
  also `default_authentication_plugin = mysql_native_password`, which is
  what 8.0's handshake greeting follows. Current BOA writes them
  automatically on Percona 8.0 and 8.4 (sql config sync, aegir2boa D-015)
  — on a target whose BOA predates that, add the lines yourself and
  restart mysql. Modern-PHP sites and `caching_sha2` users are
  unaffected — clients negotiate the switch. `check` grades this per
  D6 site as well, from what the target's server actually advertises —
  its handshake greeting, or the `authentication_policy` /
  `default_authentication_plugin` variables when the greeting cannot be
  read — so a non-native target is named before `pre-mig` pauses
  anything; a target that answers neither is reported UNKNOWN and
  accuses nobody. Past that gate the import still FAILS the site
  honestly at its serve probe instead of adopting a site that cannot
  serve — though a probe that lands before the FPM agent maps the site
  onto its php56 pool can pass on the account-default modern-PHP pool
  and the site then degrades on the agent's next pass, so fix the
  policy, don't race the probe.
- **Disk headroom**: per site roughly 2× its DB size free under
  `/var/aegir` on the source for dumps; the whole estate + 500 MB free
  under `/data/disk` on the target (`transfer` measures and refuses).
- **A shared target box can have other provisioning actors** (billing
  automation, another operator). The tools' existence gates catch a
  collision, but never pre-assume the next free `oN` account name —
  check first, and expect a dry run to fail honestly if the name got
  taken between your check and your live run.

## Stage 0 — discovery preflight

**On source**, as root:

```sh
  aegir2boa-preflight              # writes report + machine contract under /tmp
  aegir2boa-preflight --help       # options; --aegir-root for non-standard layouts
```

Read-only by contract: it writes only under `/tmp`, installs nothing,
changes no service, and its SQL is SELECT/SHOW-only. The one sanctioned
exception is the optional `drush @hostmaster status` health check (a
Drupal bootstrap writes cache tables); set `A2B_NO_DRUSH=1` to suppress it
— at the cost of a permanent `frontend_bootstrap_failed` WARN in that run.

Outputs, freshly timestamped every run:

```
  /tmp/aegir2boa-preflight.<host>.<timestamp>.txt    human report
  /tmp/aegir2boa-preflight.<host>.<timestamp>.env    machine contract
```

The report opens with the two verdicts that gate everything:

- **STAGE 1 / STAGE 2: PASS** — proceed.
- **WARN — proceed with named caveats.** WARN does not mean
  non-migratable; it lists items to resolve or consciously accept (a
  typical healthy Ægir-on-Nginx box after the stage-1 flip reports WARN on
  both stages).
- **FAIL — do not proceed with that stage.** Reasons are named tokens
  (e.g. `cluster_pack_topology`, `dump_headroom`, `boa_box_not_vanilla`).

Hard floors refuse the box with exit 3: a BOA box (use xoct instead), a
non-Ægir box, and pre-3.x Ægir. Most are caught before deep probing; a
pre-3.x box recognisable only by its hostmaster DB schema is refused
after the full probe pass. `A2B_ALLOW_BOA=1` exists for inspecting a
BOA box's data out of curiosity — it never authorises a migration.
Exit codes: 0 = report emitted, 2 = precondition failure (not root, lock
held, bad usage), 3 = floor bail (the report is still written).

The `.env` machine contract (scalars + TSV tables) is the sole input the
later stages trust — stage 2's `check` sources its verdict scalars rather
than re-discovering the box. Keep the pair with the migration record.

## Stage 1 — Apache to Nginx, in place

**On source**, as root:

```sh
  aegir2boa-stage1 --flip              # dry run: gates + baseline capture
  aegir2boa-stage1 --flip --live       # the flip
  aegir2boa-stage1 --status            # both config planes + daemons + per-site HTTP
  aegir2boa-stage1 --revert            # dry run for the way back
  aegir2boa-stage1 --revert --live     # nginx -> apache
```

Scope: concrete `http_service_type` of `apache` AND `apache_ssl`. The
`apache_ssl` → `nginx_ssl` path is drilled — flip, revert and re-flip
with the per-site certificates carried and HTTPS verified in both
directions. `cluster`/`pack` topologies are refused — flip each member
box instead.

What the live flip does, in order: installs nginx+php-fpm **without
starting daemons** (a temporary `policy-rc.d` guard; Apache keeps :80
throughout), starts the FPM pool matching the PHP series this box
already serves its sites with — provision picks the highest-sorted
socket, so a newer versioned pool started alongside it would move every
generated vhost to an interpreter the sites cannot run on, and both the
dry run and the flip REFUSE on that mismatch (the flip while Apache is
still serving) — adds the `aegir` user's
sudoers line for the exact nginx reload binary the backend will call,
enables every frontend feature the target service class needs — the
plain and SSL nginx classes come from different modules, and the dry run
already FAILS if the module providing the target class is absent from
the hostmaster codebase, because the flip would otherwise die at the
node save after a clean dry run — then flips the server node's
`http_service_type` exactly as the GUI radio would, with the node
payload carrying the estate's own port and, for an `*_ssl` class, its
`ssl_port` (queueing the server
verify that writes the nginx config tree), waits out the platform verify
cascade, then **verifies every site** (hostmaster first — the verify
cascade stops at platforms, so this per-site loop is what populates
`nginx/vhost.d`), asserting each site's nginx vhost file exists. Only
then: `nginx -t`, a **scratch-port FCGI probe** that executes real PHP
through nginx+FPM while Apache still serves — and reports the
interpreter version it reached, so a pool whose socket name lies about
its binary fails the gate too — and the daemon handover
(stop+disable apache, start+enable nginx and FPM — reboot-persistent).
Finally every site's HTTP code is compared against the pre-flip
baseline — and for every site the front end reports as encrypted, the
HTTPS response too, probed with real SNI and hostname verification, so a
flip that leaves a site on a regenerated self-signed certificate reads
as a failure.

The revert proves the Apache config without binding a port **while
nginx still serves** — the dry run parses a temp wrapper conf with
`apache2 -t -f`; the live revert re-enables the Ægir apache include
(`a2enconf aegir` where a conf-available backing file exists; a move
back into `conf-enabled`/`conf.d` on the deb-installed and apache 2.2
layouts — the tool probes where the include actually lives) and runs
`apache2ctl configtest` before nginx stops — then hands the daemons back
in reverse order and flips the config plane back. The
revert guarantee is that provision never deletes the Apache tree — so
during the whole stage-1/stage-2 window, do NOT prune
`/var/aegir/config/server_master/apache*`, the `apache2` /
`libapache2-mod-php` packages, or `/etc/apache2` state.

Timing from the drill (with the hosting-queued daemon running): flip ≈
65 s, revert ≈ 43 s, re-flip ≈ 54 s. On a cron-dispatch-only box every
queued verify waits for the next cron minute, so expect materially
longer. If the flip completes with sites differing from baseline, the
instant daemon-level fallback is printed by the tool — paste it exactly
as printed: the middle command re-enables the apache include in the form
the BOX's layout needs (`a2enconf aegir` on the conf-available layout, a
`mv` back into `conf-enabled`/`conf.d` on the others), so a snippet
copied from this page instead of from the tool could be the wrong one.

## Stage 2 — remote adoption

Place `aegir2boa-stage2` on both boxes. Verbs, verbatim from `--help`:

```
Source-resident verbs (vanilla box, root):
  peer       --target <ip>                                  [--live]
  check      --target <ip> [--route per-site|db-import] [--report <env>]
  pre-mig    --target <ip>                                  [--live]
  create     --target <ip> --account <oN> --email <e> --tree <dev|lts|pro>
             [--option EDGE] [--subscr M] [--cores 1]       [--live]
  export     --site <dom>|--all                             [--live]
  transfer   --target <ip> --account <oN> --site <dom>|--all [--live]
  proxy      --target <ip> --site <dom>|--all [--accept-http-diff]
             [--refresh]                                    [--live]
  cert-sync  --target <ip> --account <oN> [--install-cron]  [--live]
  revert     --site <dom>|--all                             [--live]
  resume                                                    [--live]
  status

Target-resident verbs (BOA box, root):
  peer       --source <ip> [--pubkey-file <f>]              [--live]
  import     --account <oN> --route per-site|db-import
             [--site <dom>|--all] [--source-fqdn <fqdn>]
             [--welcome-node]                               [--live]
  import     --account <oN> --revert-db-import              [--live]
  import     --account <oN> --reset-sites                   [--live]
  target-status --account <oN>
```

### The two routes

Stage 2 ships two adoption routes; **`check` decides eligibility from
discovery output — the route is never operator-asserted**:

- **per-site adoption (the DEFAULT).** Each site is registered natively on
  the target through the provision import ladder (`hosting-import` +
  verify), one at a time. Risk-isolated — one bad site fails alone —
  BOA-native node identity from the first write, and it needs none of the
  db-import reconciliation machinery. Cost: O(n) tasks, and the source
  frontend history (clients, users, task log) is not carried over.
- **db-import (the validated bridge for homogeneous current-3.x estates
  ONLY).** The whole vanilla hostmaster DB is imported into the fresh
  account's panel and reconciled with a mandated package of deltas (below).
  Preserves frontend history and is estate-size-independent (one DB
  operation + one reconcile pass instead of per-site task chains).
  Eligibility — `check` computes this triad from the preflight report
  plus its own enumeration, and refuses `--route db-import` if any leg
  fails:
  - every platform D7-class,
  - `hosting` schema_version at the high-water mark,
  - single-box topology (no cluster/pack, no remote web/db servers).

  Two procedural requirements ride along: the source must be in nginx
  mode (a universal `check` gate, both routes), and the
  enabled-but-code-absent module list must be acknowledged with
  `check --accept-scrub-list` — `check` only warns without the flag;
  `transfer` is what refuses a db-import run without the recorded
  acknowledgment. Anything mixed, aged, or unknown takes the per-site
  route.

### Order of operations

```
[stage 0/1 done: box on nginx, THEN a fresh preflight WARN-or-better for stage 2]
check → pre-mig → create → export → transfer →
import (ON TARGET) → proxy → cert-sync --install-cron
```

Per-site downtime window: from its `export` (a 503 goes up) to its
`proxy` swap (now served by the target through the proxy). For the
db-import route the frontend-history cutoff is the hostmaster dump
timestamp — the queue is paused from `pre-mig`, so nothing should
post-date it.

> **Source automation is never resumed on the success path.** After
> adoption the source is a proxy shell; its hostmaster must never verify
> or regenerate vhosts over the proxy files. `resume` exists only as part
> of a full-estate revert. Consequence for a long, batched migration: a
> site still waiting on the source gets no Drupal cron while the
> dispatcher is paused — size your batches so nothing waits for weeks.

### check — route + prerequisites (read-only)

**On source:**

```sh
  aegir2boa-stage2 check --target <target-ip>
  # db-import candidates, after reviewing the printed module list:
  aegir2boa-stage2 check --target <target-ip> --route db-import --accept-scrub-list
```

Validates and records, refusing on failure: the newest preflight report
under `/tmp` (root-owned, not world-writable, for THIS host, stage-2
verdict not FAIL — pass `--report <env>` to pin one), stage-1 actually
done (`vhost.d` populated, nginx-mode type of record), the CURRENT nginx
config passes `nginx -t`, BatchMode root ssh to the target works, the
target looks like a BOA box, target PHP pools, and **DB generation
parity**: both `SELECT VERSION()`s are read and recorded into
`check.env`, and a MySQL/Percona ≥ 8.0 or MariaDB ≥ 10.6 source is
REFUSED against a pre-8.0 target (its dumps carry collation names the
target rejects at import) — the refusal also blanks any earlier recorded
route, so `export` cannot ride a stale clean check. A provably ≥ 8.0
source with an unreadable target version is refused too; any other
unreadable version — the source's, or the target's when the source is
not provably a newer generation — SKIPS the gate with a named warning,
so a `check` that only warned here has not actually verified the
pairing. It computes db-import
eligibility, enumerates every enabled non-core module on the hostmaster
(the scrub review list), grades per-site PHP parity (a D6 site with no
php56 pool on the target is flagged and later SKIPPED, not blocking),
raises the same per-site flag for a D6 site when the target's DB server
advertises a non-native first factor (the Prerequisites bullet on native
auth says what to set — the point of grading it here is that it is named
before `pre-mig` pauses anything), and
records route+target for the following verbs. Re-run `check` freely; it
is always read-only.

### pre-mig — pause the source automation

**On source:**

```sh
  aegir2boa-stage2 pre-mig --target <target-ip>          # dry
  aegir2boa-stage2 pre-mig --target <target-ip> --live
```

Comments out the aegir crontab's dispatch line (saved verbatim for
`resume`), stops+disables the hosting-queued daemon (systemd or init.d,
prior state recorded), and drains in-flight backend work (up to 10
minutes). From here the estate is operationally frozen: no task dispatch,
no queue daemon.

### create — build the target account

**On source** (it drives the target over ssh):

```sh
  aegir2boa-stage2 create --target <target-ip> --account o1 \
    --email you@example.com --tree pro                    # dry, then --live
```

Runs `boa in-octopus` on the target (defaults: `--option EDGE`,
`--subscr M`, `--cores 1`), guarded for the window by the target-wide
`.dont.upgrade.octopus.on.install.cnf` flag so the post-install upgrade
churn cannot race the migration, then waits for real quiescence (process
checks, up to 30 minutes; typically a few minutes). The dry run refuses
if `/data/disk/<oN>` already exists — on a shared box that catches
another actor having taken the name. NOTE: BOA sends its welcome email
with the panel/SSH credentials to `--email` — use the address that should
receive them (yours during the window; hand over to the client later).

### export — pause + dump each site

**On source:**

```sh
  aegir2boa-stage2 export --all            # dry: per-site plan + skip reasons
  aegir2boa-stage2 export --all --live
  # or one site at a time: --site example.com
```

Per site, live: captures the HTTP baseline, raises the **503 stub** — a
shadow server block in nginx `pre.d/` that wins over the real vhost
(first-defined wins), leaving the original vhost file untouched;
`nginx -t`-gated with automatic stub removal on failure — then dumps the
site's DB **with the site's own credentials** from its drushrc (no root
DB access is ever needed on the source) into `/var/aegir/src/a2b/`, and
writes the site's manifest. Skips honestly, per site: missing vhost or
alias paths, multi-host DB, unparsable credentials, a 443 vhost whose
cert files are missing, or insufficient dump headroom. A failed dump
leaves the stub UP (data consistency over uptime) — `revert --site <dom>`
unpauses it.

On the db-import route the estate export also dumps the hostmaster DB and
puts the source panel into maintenance mode, so nothing post-dates the
frontend snapshot. That dump is accepted only if the dumper exits
cleanly AND the file ends with its own completion marker — a dump that
died after its header is refused and the estate is NOT marked exported,
so the failure surfaces at export time rather than as a broken panel
after the import (this export is what the whole adoption is rebuilt
from).

### transfer — ship everything to the target

**On source:**

```sh
  aegir2boa-stage2 transfer --target <target-ip> --account o1 --all   # dry, then --live
```

Measures total size against the target's free `/data/disk` space
(refuses without need+500 MB), then rsyncs each platform tree to
`/data/disk/<oN>/static/a2b/<platform>/` (chowned to the account — a
source-uid tree is unreadable to the account and breaks every later
import), each site dump + manifest to `/data/disk/<oN>/src/a2b/`, plus
the ssl.d trees and the nginx configs as reference copies (never into the
target's live config — vhosts are regenerated natively by verify tasks).
Drush aliases are deliberately NOT transferred on either route: vanilla
aliases carry `/var/aegir` roots that would poison the target; everything
is regenerated fresh. The route marker ships on every
transfer; on the db-import route it additionally ships `hostmaster.sql`,
the acknowledged scrub list, and the source FQDN record (`transfer`
refuses db-import without a `check --accept-scrub-list` run recorded).

### import, per-site route

**On target:**

```sh
  aegir2boa-stage2 import --account o1 --route per-site --all   # dry, then --live
  # or per site: --site example.com
```

For the window it sets `hosting_platform_automatic_site_import = 0`
(restored at the end) — a platform verify would otherwise auto-import
every `sites/` dir it finds, colliding with the explicit imports. Then,
per platform: provision-save a `platform_a2b_<name>` context, create the
platform node, and verify it (the verify registers the install-profile
package — a hard prerequisite for site imports). Per site: create its DB
and user with the site's own credentials (settings.php keeps working
unmodified; refuses to overwrite an existing DB), provision-save the site
context, `hosting-import` it and drive the import task (inline when
re-running against an already-registered node — a retry quirk the drill
caught), map its PHP version in the account's `multi-fpm.info` and wait
for the pool socket (D6 without its socket is a per-site FAIL; the site
must not serve under the account default), wait the chained verify, probe
HTTP against the source baseline, and re-enable the site's Drupal cron —
adopted sites land with cron dark by BOA design, and the source
dispatcher that used to run it is paused, so leaving it dark means silent
job loss. One site's failure never blocks the next; failed sites are
listed and stay un-adopted.

### import, db-import route

**On target:**

```sh
  aegir2boa-stage2 import --account o1 --route db-import        # dry, then --live
  # optional: --welcome-node to recreate a public frontpage
```

The dry run prints the full numbered plan. The live run opens the
**account freeze window**: the freeze marker (`log/proxied.pid`) makes
every nightly/periodic BOA agent skip the account, in-flight nightly
passes are drained, and the account's task dispatcher is **held aside**
for the duration — a raw DB import must never race task dispatch. If the
import fails mid-way the dispatcher deliberately STAYS held (a broken
panel must not dispatch); only success, `--revert-db-import`, or manual
repair restore it. The steps, each idempotent behind its own marker:

1. **Snapshot**: dump the fresh panel DB to `undo/a2b-pre-import.sql`
   (the revert point) and capture the enabled-module set into
   `undo/a2b-enabled-baseline.txt` (the reconciliation source of truth).
   The import pre-checks roughly 2× the transferred hostmaster dump +
   200 MB free under the account root for this snapshot — an extra
   headroom gate on top of the transfer one.
2. **Drop, then load with sandbox strip**: the target panel DB is dropped
   (an overlay import is BOA-to-BOA-only and would leave orphaned tables)
   and the transferred dump streamed in minus the MariaDB ≥ 10.5.25
   sandbox header line, which the Percona client rejects.
3. **Queue hygiene + neutering**: stale/pending imported tasks are
   failed-out so nothing dispatches from the source's queue, and client
   welcome emails are switched off — the imported DB holds real client
   addresses.
4. **Module scrub (acknowledged rows only)**: enabled modules whose code
   is absent from the panel platform are removed from `{system}` — but
   only modules on the `check`-time acknowledged list; anything else
   aborts the import for review. On a standard vanilla estate this list
   is empty or tiny (BOA's panel platform carries code for everything a
   stock 3.x enables).
5. **Reconcile**: platform paths are re-pointed at the landed trees, the
   BOA module set is re-enabled from the snapshot baseline (~1 s),
   `updatedb` runs (a no-op at schema high-water), features are reverted
   to code state, and per-site Drupal cron intervals are seeded hourly —
   vanilla's cron table is schema-less, so imported sites would otherwise
   have cron silently off forever.
6. **Service restore**: the Let's Encrypt service row (absent from a
   vanilla server node) is re-attached; optionally a welcome frontpage
   node (`--welcome-node`) — by default the imported admin-only
   frontpage stands.
7. **Per-site content DBs** are created and loaded with each site's own
   credentials.
8. **Identity surgery — targeted UPDATEs by nid, never a blanket
   rename.** The imported server node's title becomes the target FQDN
   (Ægir regenerates `remote_host` from that title on every server
   verify — a stale value would silently re-point the account at the old
   box over ssh); the panel site node adopts the account's own panel
   domain (`<oN>.<target-fqdn>`, the identity already on disk); the
   imported panel platform is re-pointed at the real one; the imported
   `server_localhost` node gets the TARGET account's own DB credentials
   restored from the snapshot (the imported node carries the SOURCE's —
   its verify would otherwise poison the account alias with a dead DSN;
   this failure is FATAL). History rows keep old FQDN references by
   design and are reported, not rewritten.
9. **Inline verify ladder, while the dispatcher stays held**: server
   verifies (with an assert that `remote_host` regenerated to the target
   FQDN), platform verifies, the panel site verify (FATAL on failure),
   then per site: PHP mapping, verify, and an HTTP probe against the
   source baseline. FPM socket waits are deferred until after the freeze
   lifts — the pool agent skips frozen accounts by design.
10. **Close**: panel bootstrap probe (FATAL if the panel does not
    bootstrap), stray cascade-queued tasks neutered, dispatcher restored,
    freeze lifted, deferred FPM waits + re-probes, done-marker written.

### proxy — cut each site over

**On source:**

```sh
  aegir2boa-stage2 proxy --target <target-ip> --all      # dry, then --live
  # per site: --site example.com; accept a changed-but-2xx/3xx answer:
  #   --accept-http-diff
```

Per site, gated on the **target actually answering** for that site (HTTP
probe against the manifest baseline; a differing 2xx/3xx needs
`--accept-http-diff`, anything else is a SKIP). The gate is not
status-only: before the per-site probes the tool fingerprints what the
target answers for an impossible hostname, and refuses any site whose
200 response body is byte-identical to that fingerprint — a BOA box
answers an unknown Host with its "Under Construction" catch-all, so a
200 alone proves nothing. This refusal is unconditional:
`--accept-http-diff` tolerates a DIFFERENT status but can never accept a
target that is not serving the site at all; hitting it means the import
did not produce a serving vhost for that site. Then: the real vhost is moved
aside to the dotfile `.<domain>` (THE revert artifact) and a proxy vhost
pointing at the target written in its place; for https sites a per-site
proxy cert store is seeded from the site's existing cert files and an
https proxy vhost added. `nginx -t`-gated: on failure the swap is undone
and the 503 stub keeps pausing the site. On success the stub is removed —
the site now serves live from the target through the source proxy.

`proxy --all` also puts the OLD panel domain behind a permanent 503 stub
(both routes): the panel identity moved to `<oN>.<target-fqdn>`, so the
old panel URL must not proxy anywhere. Tell the client the new URL.

The proxy templates are embedded, vanilla-adapted equivalents of BOA's
own proxy vhosts (BOA's originals need the BOA nginx build and Octopus
cert paths, so they cannot be dropped onto a distro nginx verbatim). The
emitted https vhost also adapts its HTTP/2 syntax to the source's own
nginx version — the standalone directive only where that nginx knows it,
the listen-parameter form otherwise — because a vanilla box runs the
distribution build, not BOA's. The
catch-all location also forwards `/.well-known/acme-challenge/` — so the
TARGET can mint and renew real Let's Encrypt certs for domains whose DNS
still points at the source, for the whole proxy window.

Proxy vhosts carry the vanilla vhost's whole `server_name` set **plus
`www.<domain>`** even when the vanilla vhost never served it. BOA's LE
requests a SAN certificate for the bare name AND `www.` by default, and
the adopting BOA box answers `www.` itself — but the challenge for it
arrives at THIS box, and without the alias it lands on the catch-all and
the whole certificate order fails (measured live 2026-08-11: bare name
validated through the proxy, `www.` got 404, `cert.pem` left empty). A
name the client's DNS does not resolve simply never arrives, so the
extra alias is inert on estates without `www.` records. It is also
skipped, with a warning, when `www.<domain>` is served on the source by a
conf of its own — an estate that manages it as a separate site, which
vanilla allows. `vhost.d` is included by a sorted glob and the
first-defined server wins (nginx only warns, and `nginx -t` still passes),
so claiming that name would capture an unmigrated site's traffic; on those
estates the `www.` challenge has to come from that other conf, and both
the dry run and the swap say so by name.

`proxy --refresh` (dry, then `--live`) re-renders the proxy vhost(s) of
already-proxied sites in place, from the dotfile original plus the
CURRENT templates — for when a template fix must reach a live window
without the revert → re-export loop. No markers move, the dotfile is
untouched, and the previous conf is restored if `nginx -t` fails.

### cert-sync — keep the proxy's certs fresh (https estates)

**On source:**

```sh
  aegir2boa-stage2 cert-sync --target <target-ip> --account o1 --install-cron         # dry
  aegir2boa-stage2 cert-sync --target <target-ip> --account o1 --install-cron --live
```

For each proxied https site, pulls the target account's live LE cert pair
into the source's proxy cert store and reloads nginx (rollback to the
previous pair if `nginx -t` fails). `--install-cron` writes
`/etc/cron.weekly/a2b-cert-sync` so a months-long proxy window never
serves an expired certificate: nobody renews ON the proxy box — it
mirrors the box that does. Remove that cron at decommission (stage 3).

> **The target does not obtain its own certificates for you.** Adopted
> sites arrive dark by design — cron and Encryption both off — so the
> target holds NO certificate for a site that is live on HTTPS today.
> Nothing looks wrong while you are in the window, because the proxy is
> serving the SOURCE's certificates; it becomes an outage the moment DNS
> moves. Enable Encryption per site in the target panel and let LE issue
> BEFORE you repoint anything. ACME reaches the target through this
> proxy, so issuance works while DNS still points at the old box.
>
> `cert-sync` refuses to report success while any proxied HTTPS site has
> no certificate on the target: it names each one and exits non-zero.
> Measured on the 2026-08-11 drill, where it reported `0 refreshed,
> 2 MISSING on the target`.
>
> The refresh half is drilled too (same day, same estate): with Encryption
> enabled on the target and LE issued through the proxy window,
> `cert-sync --live` reported `2 refreshed`, exit 0, reloaded nginx, and
> the proxy served the target-issued certificates from then on
> (serial-verified via `openssl s_client`). Two practical notes from that
> drill: BOA requests a SAN certificate (bare + `www.`) by default, which
> is why proxy vhosts carry `www.<domain>`; and back-to-back verifies can
> collide on the LE tooling's per-account lock — enable and verify sites
> ONE AT A TIME, and re-run the verify if a run reports a lock abort.
>
> **db-import route nuance.** Sites adopted per-site are registered fresh
> on the BOA panel, whose defaults add the `www.` alias — so their vhosts
> answer the `www.` ACME challenge. The db-import route imports the
> vanilla panel as-is, and vanilla adds no automatic `www.` alias, so a
> default SAN issuance fails its `www.` challenge on the target's
> catch-all. Before enabling Encryption on a db-import-adopted site,
> either add its `www.` alias in the target panel, or request a bare-name
> certificate by creating the empty control file
> `<oN>/static/control/ssl-no-san-<domain>.info`.

### Reverts — the way back, until DNS moves

Everything below is drilled. The one rule that matters: **a reverted site
must be re-exported before any retry** — the moment it serves locally
again its transferred dump is stale, and a cutover from a stale dump
silently loses writes. The tools enforce this by clearing the export and
transfer markers on revert.

**Single site, on source:**

```sh
  aegir2boa-stage2 revert --site example.com          # dry, then --live
```

Restores the original vhost (dotfile back over the proxy vhost), removes
the https proxy vhost and the 503 stub, reloads nginx. The site serves
locally again as if nothing happened. It does NOT touch the target copy —
reset that before any retry (below).

**Whole estate:** `revert --all --live`, then `resume --live` (restores
the crontab dispatch line and the hosting-queued daemon exactly as
recorded, and clears the source panel's maintenance mode). `resume`
refuses while any site is still paused or proxied.

**On target:**

```sh
  aegir2boa-stage2 import --account o1 --reset-sites --live        # per-site route
  aegir2boa-stage2 import --account o1 --revert-db-import --live   # db-import route
```

`--reset-sites` drops exactly the site DBs this tool loaded (marker-
fenced — it can never touch a DB it did not create). `--revert-db-import`
additionally restores the panel DB from the pre-import snapshot and
returns the held dispatcher. Both print the same reminder: a retry needs
a fresh export+transfer.

### Monitoring a migration

```sh
  aegir2boa-stage2 status                       # on source: route, markers, per-site [P E T X] + live HTTP
  aegir2boa-stage2 target-status --account o1   # on target: route, freeze state, step markers
```

Source state lives under `/var/aegir/log/a2b/` (state, manifests, per-site
markers), target state under `/data/disk/<oN>/log/a2b/`; dumps under
`src/a2b/` on both sides; the pre-import snapshot under
`/data/disk/<oN>/undo/`. A crashed run's stale lock
(`/var/run/aegir2boa-stage2.*.lock`) is taken over automatically once its
recorded pid is dead.

## Stage 3 — DNS cutover and source decommission

The proxy window ends when DNS points every domain at the target and the
old box is retired. Until DNS moves, the per-site dotfile revert exists;
after it, the target's own backups are the safety net. Take stage 3
deliberately:

1. **Pre-lower TTLs.** The preflight recorded the estate's DNS TTLs; get
   every A/AAAA record's TTL down (300–3600 s) at least one old-TTL
   period BEFORE the cutover, so the switch propagates fast.
2. **Repoint DNS** for every migrated domain to the target IP. Do it
   site-by-site or estate-wide; the proxy keeps covering stragglers
   either way, so this is not a downtime event.
3. **Mail and network identity.** A new IP invalidates any SPF `ip4:`
   record pinned to the old box and needs PTR/rDNS set up at the new
   provider; if the old box received mail (MX) or ran authoritative DNS
   (BIND/hosting_dns), move those roles explicitly — the migration tools
   do not.
4. **Re-home the jobs that watched the old box**: monitoring/alerting,
   external backup jobs, anything in root's crontab an operator added.
   The source's Ægir automation is already paused; leave it paused.
5. **Verify traffic has left the proxy.** Watch the source's nginx access
   logs go quiet per domain (residual hits = stale DNS caches or
   overlooked records), and spot-check `dig +short <domain>` against the
   target IP.
6. **Retire the proxy.** Host policy decides the window (days to months).
   When it closes: remove `/etc/cron.weekly/a2b-cert-sync`, archive what
   the record needs (the preflight `.txt`/`.env`, `/var/aegir/log/a2b/`,
   the migration log), snapshot the box if the provider makes that cheap,
   then power it off.
7. **Clean the target**: remove the source's CSF allow/ignore lines
   (`csf -ra` after), drop the migration key from
   `/root/.ssh/authorized_keys`, and optionally the tool copy and the
   landed `src/a2b/` artifacts once the estate has run clean past a
   backup cycle.

## Troubleshooting quick reference

| Symptom | Meaning / action |
|---|---|
| `check` dies: no preflight report / wrong host | run `aegir2boa-preflight` on THIS box now (reports are per-host and die with `/tmp`) |
| `check` dies: stage-2 verdict FAIL | resolve the named reasons; re-run preflight |
| `check` dies: `http_service_type=apache… - source is not nginx-mode` on a box that is on nginx | the newest preflight report predates the stage-1 flip — re-run `aegir2boa-preflight`, then `check` |
| `check` dies: current nginx config fails `nginx -t` | fix the box first — the tool refuses to build on a broken config |
| `check` dies: source DB newer generation than target | the source runs MySQL/Percona ≥ 8.0 (Ubuntu 20.04+ default) or MariaDB ≥ 10.6 and the target is pre-8.0 — use a Percona 8.4 target for this source |
| `--live` refused: no prior CLEAN dry run | run the dry form of the same verb+scope first (every failed live consumes the token) |
| `create` waits forever | another Octopus operation on the target; it times out at 30 min with a warning — verify quiescence manually before `import` |
| `export` skips a site | the printed reason (missing vhost/alias, multi-host DB, bad creds, missing cert files, headroom); fix or accept, re-run |
| dump fails mid-export | the 503 stub STAYS up (consistency over uptime); `revert --site <dom>` to unpause |
| `import` (db-import) fails mid-run | dispatcher stays held on purpose; fix and re-run `import` (steps are idempotent), or `--revert-db-import` |
| site fails its verify/probe on target | it is listed and skipped; `proxy` will refuse it (probe gate) — fix, re-import that site |
| `proxy` skips a site: HTTP diff | target answers differently than the baseline; re-check the site on the target, or `--accept-http-diff` if the change is expected |
| `proxy` skips a site: CATCH-ALL page | the target is not serving that site at all — its 200 is the box's own "Under Construction" answer; re-check the site's import. `--accept-http-diff` cannot override this |
| FPM socket wait times out | the pool agent needs a pass (runs every few minutes; frozen accounts are skipped until the freeze lifts); D6 sites must not be proxied without their pool |
| lock held | another run of the same verb+scope is live; stale locks self-clear when the pid is dead |
| anything else | read `/var/log/aegir2boa-stage2.log`, then the named hostmaster task log (`node/<nid>` on the panel) |

## Notes

- The stage-2 tool takes nothing for granted about the source: per-site
  dumps use each site's own DB credentials, `mysqldump` not mydumper, and
  every remote action is plain root ssh + rsync.
- Idempotency and resume: every verb re-run skips what its markers say is
  done; `status`/`target-status` show exactly where a migration stands.
- Parallel estates: locks and markers are scoped per account and site, so
  one source can migrate into two target accounts sequentially (the
  `create` marker is account-scoped), but never run two acting verbs on
  the same scope concurrently.
- The old panel's task history (db-import route) honestly keeps source
  FQDN strings in old task rows; identity surgery re-points only the
  live identity fields and reports the rest.
