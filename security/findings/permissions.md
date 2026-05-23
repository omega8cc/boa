# Findings: File and Directory Permissions

Covers world-writable paths, unsafe temp file handling, overly permissive log/config files, and ownership issues.

Findings are appended below as they are discovered. Each entry follows the schema defined
in CLAUDE.md. Most-recent findings appear at the bottom.

---

## Audit scope coverage

- All `chmod`/`chown` calls in `aegir/tools/system/*.sh`, `aegir/tools/bin/*.sh`,
  `lib/functions/*.inc`, and the top-level installer text files.
- All `/tmp/*` and `mktemp` usages.
- Log-directory and credential-file permission setup.

---

## [HIGH] daily.sh `chown -L -R` follows attacker-controlled symlinks inside `${_Dir}/files`, `${_Dir}/private`
**File:** aegir/tools/system/daily.sh  (lines 1725, 1738, 1745)
**Category:** permissions (also tracks privilege-escalation)
**Status:** PATCHED in this commit

### Description
`daily.sh` is the cron-driven daily runner that runs as root from
`/etc/crontab` (`15 4 * * * ... bash /var/xdrago/daily.sh`). Inside its
per-site loop the script parses `_Dir` (the site_path) and `_Plr` (the
platform root) from the Drush alias file at
`${_usEr}/.drush/${_Dan}.alias.drushrc.php` (lines 2406, 2412), then runs
`chown -L -R ${_HM_U}:www-data` on `${_Dir}/files`, `${_Dir}/private`, and
`${_Dir}/private/config`.

`-L` is the GNU option that explicitly tells chown to follow every symlink
during the recursive walk and operate on the target. A symlink planted
inside `${_Dir}/files/` (for example as part of an uploaded tar archive,
which Adam confirmed in the category-1 review is the realistic threat
vector even when end users cannot directly create symlinks) redirects the
recursive chown to a system path. Combined with the threat model already
established for category 1 (aegir/HM_U compromise via Drupal vuln), this is
the same root-ownership-escalation chain in the cron runner that we already
patched in the NOPASSWD-sudo helpers.

The Drush alias file is written by aegir-context Hostmaster tasks; a
compromised HM_U user can also rewrite the alias to point `site_path` at
an arbitrary directory under `/data/disk/`. Without a path-prefix
validation, the daily runner would happily walk and chown arbitrary trees.

### Evidence
```bash
# line 2406
_Dir=$(cat ${_usEr}/.drush/${_Dan}.alias.drushrc.php \
  | grep "site_path'" \
  | cut -d: -f2 \
  | awk '{ print $3}' \
  | sed "s/[\,']//g" 2>&1)
# line 1725
chown -L -R ${_HM_U}:www-data ${_Dir}/files &> /dev/null
# line 1738
chown -L -R ${_HM_U}:www-data ${_Dir}/private &> /dev/null
# line 1745
chown -L -R ${_HM_U}:www-data ${_Dir}/private/config &> /dev/null
```

### Fix
Two-layer defence matching the category-1 helpers:
1. Add `_validate_safe_dir` (realpath canonicalisation + prefix allowlist
   on `/data/disk/`, `/var/aegir/`, `/home/`). Apply to `_Dir` and `_Plr`
   immediately after they are parsed from the alias; skip the site loop
   iteration if validation fails.
2. Replace `chown -L -R` with `chown -h -R` on every line. Adam confirmed
   in category 1 that BOA-managed legacy symlinks (shared D6/D7 core)
   live in BOA-managed trees end users cannot write — `-h` keeps those
   symlinks' own ownership in sync without dereferencing the target, so
   the legacy layouts remain functional and attacker symlinks are inert.

### Patch commit
PATCHED — see commit message below.

---

## [MEDIUM] daily.sh broader chown/chmod surface lacks `-h` and symlink prechecks
**File:** aegir/tools/system/daily.sh  (lines 395, 441, 517, 543, 561, 972, 998, 1047, 1069, 1106, 1130, 1166, 1190, 1564, 1568, 1589, 1595, 1648, 1655, 1660, 1682, 1699, 1700, 1710, 1714, 1717, 1729–1736, 1741–1744, 1910, 1928 — chown; 396, 442, 518, 544, 562, 973, 999, 1048, 1070, 1107, 1131, 1167, 1191, 1565, 1569, 1600–1609, 1667–1677, 1702, 1703, 1728 — chmod)
**Category:** permissions
**Status:** NEEDS-REVIEW

### Description
Roughly 30 `chown` and 20 `chmod` calls operate on caller-controlled paths
derived from `_Dir`, `_Plr`, `_use_Plr`, and `_DIR_CTRL_F`/`_PLR_CTRL_F`
without `-h` (chown) or `[ ! -L ... ]` prechecks (chmod). Each single-file
chown without `-h` will dereference a symlink at the named child path and
operate on the target — so a `chown ${_HM_U}:www-data ${_Dir}/files/llms.txt`
where `llms.txt` is symlinked to `/etc/shadow` makes `/etc/shadow` owned by
the tenant. A `chmod 0440 ${_Dir}/civicrm.settings.php` where that file is
symlinked to `/etc/sudoers` makes `/etc/sudoers` mode 0440 (which sudo
still accepts, but the operator may not — operational impact, not
escalation, but in either case wrong).

The path-prefix validation patched alongside finding #1 above closes the
worst case (alias-file tampering to point at `/etc`). The chown/chmod
follow-the-symlink behaviour is the residual surface.

This is the same vulnerability class as the category-1 helpers we patched
in `fix-drupal-{platform,site}-{ownership,permissions}.sh`, applied here
to the per-site loop in `daily.sh`. The fix shape is identical
(`chown -h`, `_chmod_safe` wrapper) but the surface is much larger — every
chown line and every direct chmod line needs converting.

### Evidence
A few examples (full list in line range above):
```bash
# line 517 (chown without -h, attacker-symlinked llms.txt)
chown ${_HM_U}:www-data ${_Dir}/files/llms.txt &> /dev/null
# line 1700 (multi-file chown, brace-expanded to symlinked paths)
chown ${_HM_U}:www-data \
  ${_Dir}/{local.settings.php,settings.php,civicrm.settings.php,solr.php} &> /dev/null
# line 1703 (direct chmod, follows symlink)
chmod 0640 ${_Dir}/civicrm.settings.php &> /dev/null
# line 1717-1719 (chown -R without -h, follows top-level symlink target dir's metadata)
chown ${_HM_U}:users \
  ${_Dir}/drushrc.php \
  ${_Dir}/{modules,themes,libraries} &> /dev/null
```

### Fix
Convert all chown calls on caller-controlled paths to `chown -h` (or
`chown -h -R` for recursive). Wrap every direct chmod on a caller-
controlled path with `[ ! -L "${path}" ] && chmod ...` or use a
`_chmod_safe` helper modelled on the one introduced in the category-1
helpers. `find -type d / -type f` recursive chmods are already safe (the
predicates exclude symlinks).

The path-prefix validator landed alongside finding #1 mitigates the
worst case (a tampered alias pointing `_Dir` at `/etc`). The residual
attack — a symlink at a known child path inside a valid `_Dir` — is
defended only by attempting these lines one-by-one.

NEEDS-REVIEW: this is a workstream-sized refactor (~50 lines in a 3540-
line file that runs as root from cron). Recommend scheduling against
`boa-modernisation` so the convert-to-helper change can be
shellcheck-verified and Tier-3-tested in isolation, rather than mixing it
into the audit's defensive-fix pass.

### Patch commit
PENDING — deferred to a focused refactor pass. See DECISIONS.md.

---

## [MEDIUM] `/var/tmp/fpm` opcache lockfile path is world-writable without sticky bit
**File:** aegir/tools/system/monitor/check/php.sh  (line 400)
**Category:** permissions
**Status:** PATCHED in this commit

### Description
`opcache.lockfile_path=/var/tmp/fpm` is set in
`aegir/conf/php/fpm-pool-common.conf` and shared across every PHP-FPM
pool (every tenant). PHP creates a lock file per pool inside this
directory. The bootstrap in `monitor/check/php.sh` ensures the directory
exists with `chmod 777`. Without the sticky bit, any tenant whose PHP-FPM
pool runs as a per-tenant uid can delete another tenant's opcache lock
file, causing opcache locking errors for that tenant — a cross-tenant
denial-of-service.

This is the standard `/tmp`-style scratch directory model: world-writable
+ sticky (1777). The current mode (777, no sticky) is the only difference.

### Evidence
```bash
# line 398-401
if [ ! -e "/var/tmp/fpm" ]; then
  mkdir -p /var/tmp/fpm
  chmod 777 /var/tmp/fpm
fi
```

### Fix
Change `chmod 777` to `chmod 1777`. Idempotent: re-running the script
will keep the sticky bit set. No functional change for legitimate pool
processes (each pool can still create and write its own lockfile); only
cross-tenant deletion is blocked.

### Patch commit
PATCHED — see commit message below.

---

## [MEDIUM] `/var/log/php*` made world-writable on every install/upgrade
**File:** lib/functions/helper.sh.inc  (line 1035)
**Category:** permissions
**Status:** PATCHED in this commit

### Description
`/var/log/php` and any sibling directory matching `/var/log/php*` (e.g.
`/var/log/php85`, if present) get `chmod 777`. The directory holds:
- `php{NN}-fpm-error.log` — written by the PHP-FPM master (root) before
  privilege drop; appended to by workers (tenant uid).
- `fpm-$pool-slow.log` and `opcache-$pool-error.log` — written per-pool
  (tenant uid).
- `error_log_NN` / `error_log_cli_NN` — per-PHP-version error log.

With dir mode 0777, any local user can:
- List the directory and enumerate every tenant's pool name (the filenames
  reveal them) — cross-tenant information disclosure.
- Create arbitrary files in `/var/log/php/`, which may shadow expected
  log paths if PHP-FPM is later restarted (filename collision possible).
- Delete files via brace-expansion or wildcard `rm` (sticky-bit absence)
  — cross-tenant DoS.

The PHP-FPM master runs as root and opens log files before dropping
privilege. Mode 0755 root:root is sufficient: master creates files at
pool start (root-privileged), workers append via inherited fd.

### Evidence
```bash
# line 1034-1035
mkdir -p /var/log/php
chmod 777 /var/log/php* &> /dev/null
```

### Fix
Change to `chmod 0755`. Add `chown root:adm` for parity with the standard
syslog-managed log directory pattern (adm group can read for log
shipping). Files inside retain their existing per-pool ownership.

### Patch commit
PATCHED — see commit message below.

---

## [LOW] `/data/conf/arch/log` chmod 0777 — vestigial empty directory
**File:** lib/functions/system.sh.inc:6113; lib/functions/satellite.sh.inc:5143
**Category:** permissions
**Status:** PATCHED in this commit

### Description
Both call sites do `mkdir -p /data/conf/arch/log` followed by `chmod 0777`.
The surrounding `mv -f /data/conf/global.inc-pre* /data/conf/arch/` lines
move files into `/data/conf/arch/` (the parent), never into `arch/log`.
Grep across the codebase finds no writer to `/data/conf/arch/log`. The
directory is vestigial dead code that ships at mode 0777 for no functional
reason.

Risk: a local user can create files inside `/data/conf/arch/log/` that
have no effect today, but a future feature that reads this directory and
treats its content as trusted would inherit the wide-open creator
surface.

### Evidence
```bash
# system.sh.inc:6112–6117 (identical at satellite.sh.inc:5142–5147)
mkdir -p /data/conf/arch/log
chmod 0777 /data/conf/arch/log
mv -f /data/conf/global.inc-pre* /data/conf/arch/     &> /dev/null
mv -f /data/conf/global/*inc-pre* /data/conf/arch/    &> /dev/null
mv -f /data/conf/global.inc-before* /data/conf/arch/  &> /dev/null
mv -f /data/conf/global.inc-missing* /data/conf/arch/ &> /dev/null
```

### Fix
Change `chmod 0777 /data/conf/arch/log` to `chmod 0755 /data/conf/arch/log`.
Root remains the owner (default mkdir as root); other users can traverse
and list but not write. If `/data/conf/arch/log` is truly unused, a
separate cleanup commit can delete the `mkdir -p .../log` entirely; that
is left to the boa-modernisation pass.

### Patch commit
PATCHED — see commit message below.

---

## [LOW] `chmod -R 777 /opt/tmp` recursive on BOA scratch root
**File:** lib/functions/helper.sh.inc  (line 538)
**Category:** permissions
**Status:** NEEDS-REVIEW

### Description
```bash
chmod -R 777 /opt/tmp &> /dev/null
find /opt/tmp/boa -type d -exec chmod 0755 {} \; &> /dev/null
find /opt/tmp/boa -type f -exec chmod 0644 {} \; &> /dev/null
```

The recursive 777 hits everything under `/opt/tmp`. The two follow-up
`find` calls re-set only `/opt/tmp/boa` — any other subdirectory under
`/opt/tmp/` keeps mode 0777, and the recursive chmod also affects every
file/dir without the sticky bit.

The recursive `chmod -R 777` also runs on cmdline-arg `/opt/tmp` itself.
With GNU chmod following the cmdline symlink (if `/opt/tmp` were ever a
symlink), this could redirect onto an arbitrary path — but `/opt/tmp` is
normally a real directory created by BOA install and not user-controlled,
so this is theoretical.

Risk shape: BOA scratch operations use predictable filenames under
`/opt/tmp/` (e.g. `/opt/tmp/testecho*` for MySQL command tests). Without
sticky bit, any local user can interfere with these files. Same DoS class
as `/var/tmp/fpm`, lower priority because the test files are short-lived
and any failure causes the BOA subsystem to retry or log.

### Fix
Replace the first line with `chmod 1777 /opt/tmp` (top-level only, with
sticky bit). Keep the two `find` calls for `/opt/tmp/boa`. Optional: add
`-h` to the chmod (no-op for non-symlink; defense-in-depth).

NEEDS-REVIEW: `chmod -R 777` predates the 1777-with-find pattern and may
reflect an explicit choice. Asking before patching since `helper.sh.inc`
is sourced by every BOA install/upgrade run and `_check_root` chain.

### Patch commit
PENDING — awaiting confirmation.

---

## [LOW] satellite.sh.inc:1462 transient `chmod 777 /data /data/disk /data/conf` during contrib update
**File:** lib/functions/satellite.sh.inc  (line 1462)
**Category:** permissions
**Status:** INFO

### Description
`_satellite_o_contrib_update_global` (and the calling chain) opens up
`/data /data/disk /data/conf /data/disk/<all>/aegir/distro` to mode 0777
during the contrib-update phase. A later phase (lines 5095, 5118) reverts
these to mode 0711. The 777 window exists only while the installer/upgrader
is operating as root, during which local non-root access is bounded
(everyone else runs through Aegir hostmaster which is not active during
upgrade). No clear exploit path observed.

### Fix
Optional hardening: change to `chmod 0775` for the duration of the
contrib update, with the existing 0711 narrowing at the end of the
upgrade still applying. Or convert the whole flow to use explicit chowns
rather than wide chmods. Not actioned in this audit.

### Patch commit
N/A.

---

## [LOW] predictable `/tmp/virtwhat.$$.strace` filename
**File:** BOA.sh.txt  (line 797); lib/functions/helper.sh.inc  (line 713)
**Category:** permissions
**Status:** INFO

### Description
A virtualization-detection helper writes strace output to
`/tmp/virtwhat.$$.strace` using only `$$` (PID) for uniqueness. With
`/tmp` mode 1777, a local user who can guess the next PID can pre-create
a symlink at that path; the BOA script would then write its strace output
through the symlink, potentially overwriting whatever the symlink points
at. The window is small (PIDs randomise on modern Linux, install runs
one-shot) and the strace output content is unlikely to be useful to an
attacker as overwrite payload, so risk is low.

### Fix
Use `mktemp -t virtwhat.XXXXXX.strace` and capture the returned path.
One-line change. Not actioned in this audit because the install context
runs at machine bring-up where no untrusted users exist yet.

### Patch commit
N/A.

---

## [INFO] only 2 mktemp uses in the entire codebase
**File:** aegir/tools/system/manage_solr_config.sh:1091, 1203
**Category:** permissions
**Status:** INFO

### Description
The two Solr config helpers use `mktemp /tmp/solr_..._XXXXXX.json` to
allocate scratch JSON. Every other root-context script in BOA uses
static `/tmp/...` paths or scripts within `/opt/tmp`. The static-path
approach is defensible when filenames are unguessable in practice (e.g.
include `$$`) but a code-style standard of `mktemp` for any new scratch
file would be a useful baseline for the boa-modernisation pass.

### Fix
N/A — codebase-style recommendation only. Worth a checklist item in
the modernisation pass: "any new scratch file uses mktemp, with the
intermediate directory under a root-owned location like /run/boa/".

### Patch commit
N/A.

---

## [INFO] /var/log/boa/ directory permissions not explicitly set; aegir_install.log briefly exposes OTLU
**File:** aegir/tools/system/daily.sh:3279; aegir/tools/system/minute.sh:107; aegir/tools/system/usage.sh:1035; lib/functions/master.sh.inc:1219
**Category:** permissions
**Status:** INFO

### Description
`/var/log/boa/` and `/var/log/boa/le/`, `/var/log/boa/daily/`,
`/var/log/boa/usage/` are created by `mkdir -p` calls without explicit
chmod/chown. They inherit the running umask (typically 0022 → mode 0755
root:root). Files written inside inherit umask too (typically 0644
root:root unless chowned).

The one explicitly handled file is `/var/log/boa/aegir_install.log`,
chowned to `aegir:aegir` at master.sh.inc:1219. The file mode is left
at the creator default (0644 unless umask differs). Because `/var/log/boa`
is mode 0755 (everyone can list and stat), every local user can see the
log file exists and stat its size. The file contains the Aegir
**one-time-login URL** (OTLU), extracted from this log by `master.sh.inc:1423`
and `satellite.sh.inc:5168`. Mode 0644 means any local user can read it —
including the OTLU — within the URL's TTL.

OTLU is single-use and short-lived, so the window is small. But "anyone
on the box can read it and race to redeem it before the admin does" is
a real exposure.

### Fix
Recommend `chmod 0600 /var/log/boa/aegir_install.log` once the OTLU has
been extracted (existing extraction is at master.sh.inc:1423). Or:
`mkdir -p /var/log/boa && chmod 0750 /var/log/boa && chown root:aegir
/var/log/boa` so only aegir (which writes the log) and root can read it.

Not actioned in this audit because the OTLU lifecycle is handled in
master.sh.inc which is central installer plumbing — risk of touching
this near the start of category-3 work is higher than the reward.
Recommend scheduling against the credential-exposure category (6) pass.

### Patch commit
N/A — flagged for credential-exposure follow-up.
