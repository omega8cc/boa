# Findings: Privilege Escalation

Covers lshell escape vectors, sudo rule abuse, SUID/SGID issues, and privilege re-acquisition races.

Findings are appended below as they are discovered. Each entry follows the schema defined
in CLAUDE.md. Most-recent findings appear at the bottom.

---

## [HIGH] chown -L -R follows attacker-controlled symlinks (fix-drupal-site-ownership.sh)
**File:** aegir/tools/bin/fix-drupal-site-ownership.sh  (lines 86, 98, 108, 113)
**Category:** privilege-escalation
**Status:** PATCHED

### Description
The script is invoked through a NOPASSWD sudo rule installed for both the `aegir` master
user (lib/functions/master.sh.inc:767) and every Octopus admin `_USER` (lib/functions/satellite.sh.inc:2872,2884).
The script's `--site-path` argument controls a path the calling user already owns (under
`/var/aegir/...` or `/data/disk/oN/...`). Inside the script, ownership is changed with
`chown -L -R` — the `-L` flag tells chown to dereference symbolic links during the recursive
walk and operate on their targets.

A caller able to place a symlink inside the validated `${site_path}` tree (e.g. replace
`files/` with a symlink to `/etc`) causes chown to recursively change ownership of the
linked-to filesystem subtree. This converts a compromised `aegir`/Octopus-admin account
(the realistic threat model for BOA, since the Drupal Hostmaster front-end runs as `aegir`)
into full root file ownership control — e.g. taking ownership of `/etc/shadow`,
`/etc/sudoers.d/`, or `/etc/cron.d/`.

The `${site_path}/settings.php` regular-file check at line 49 does not protect against this:
the attacker can satisfy it with a real `settings.php` file alongside symlinks for
`files/`, `private/`, `modules/`, `themes/`, and `libraries/`.

### Evidence
```
# line 86
chown -R ${script_user}:users \
  ${site_path}/{modules,themes,libraries}/* &> /dev/null
...
# line 98
chown -L -R ${script_user}:www-data ${site_path}/files &> /dev/null
...
# line 108
chown -L -R ${script_user}:www-data ${site_path}/private &> /dev/null
# line 113
chown -L -R ${script_user}:www-data ${site_path}/private/config &> /dev/null
```

### Fix
Replace `chown -L -R` with `chown -h -R` (or drop `-L` and add `-h --no-dereference`)
and ensure all chown invocations on caller-controlled paths use `-h`. Additionally,
validate the resolved canonical path (`realpath -e`) of `${site_path}` against an expected
prefix (e.g. `/var/aegir/`, `/data/disk/`) before any chown.

NEEDS-REVIEW: confirm with Adam that BOA does not intentionally rely on `-L` semantics for
any platform layout (e.g. shared libraries directory exposed via symlink that must be
chowned). See "Patch confirmation request" at the bottom of this file.

### Patch commit
PATCHED in this commit. chown -L -R replaced with chown -h -R, every chown
on caller-controlled paths now uses -h, _validate_path_prefix added at
the top of the script (rejects anything that does not resolve under
/var/aegir/, /data/disk/, or /home/).

---

## [HIGH] chown -R changes ownership of symlink targets (fix-drupal-platform-ownership.sh)
**File:** aegir/tools/bin/fix-drupal-platform-ownership.sh  (lines 79, 94, 96, 99–103, 105–110, 113)
**Category:** privilege-escalation
**Status:** PATCHED

### Description
Same NOPASSWD sudo entry point as the site-ownership script. Without `-h`, `chown` on
a path that is a symlink (e.g. a brace-expanded glob result like
`${drupal_root}/sites/all/modules`) dereferences the symlink and operates on the target.
With `-R` (and the default `-P` walk policy) the directory walk does not descend through
symlinks, but the cmdline-supplied symlinks themselves still have their target's
ownership rewritten. An attacker controlling `${drupal_root}` can replace e.g.
`sites/all/modules` with a symlink to `/etc` and obtain `aegir:users` ownership of `/etc`.

The validation at lines 49–55 only checks that `${drupal_root}/sites/` is a directory and
that one of two `system.module` paths exists; it does not check for symlinks.

### Evidence
```
# line 79
chown ${script_user}:users ${drupal_root}
# lines 94, 96
chown -R ${script_user}:users ${drupal_root}/vendor
chown -R ${script_user}:users ${drupal_root}/../vendor
# lines 99–103
chown -R ${script_user}:users \
  ${drupal_root}/sites/all/{modules,themes,libraries,drush}
chown -R ${script_user}:users \
  ${drupal_root}/{modules,themes,libraries,includes,misc,profiles,core}
# lines 105–110
chown ${script_user}:users \
  ${drupal_root}/sites/all/drush/drushrc.php \
  ${drupal_root}/sites \
  ${drupal_root}/sites/* \
  ${drupal_root}/sites/sites.php \
  ${drupal_root}/sites/all
# line 113
chown -R ${script_user}:www-data \
  ${drupal_root}/sites/all/libraries/tcpdf/cache &> /dev/null
```

### Fix
Add `-h` to every chown invocation. Validate `realpath -e "${drupal_root}"` against an
expected prefix. Reject the request if any component in the validated path is a symlink
pointing outside the allowed root.

NEEDS-REVIEW: same as above — confirm no intentional cross-tree symlinks need to be
chowned.

### Patch commit
PATCHED in this commit. chown -L -R replaced with chown -h -R, every chown
on caller-controlled paths now uses -h, _validate_path_prefix added at
the top of the script (rejects anything that does not resolve under
/var/aegir/, /data/disk/, or /home/).

---

## [HIGH] chmod on glob-expanded attacker-controlled paths follows symlinks (fix-drupal-platform-permissions.sh)
**File:** aegir/tools/bin/fix-drupal-platform-permissions.sh  (lines 110, 113–117, 126–133, 139–141, 144–146, 152)
**Category:** privilege-escalation
**Status:** PATCHED

### Description
Invoked through the same NOPASSWD sudo rule. GNU `chmod` on command-line arguments
follows symlinks and changes the target's mode. Recursive `find -type d/-type f -exec chmod`
calls are safe (find without `-L` does not match symlinks and the `-type` predicates
exclude them), but the direct `chmod` calls on glob-expanded paths and known filenames are not.

For example, `chmod 02775 ${drupal_root}/web` with `${drupal_root}/web` symlinked to
`/etc` makes `/etc` setgid and world-writable. `chmod 0644 ${drupal_root}/sites/x.php`
with that path symlinked to `/etc/shadow` makes the system shadow file world-readable.
`chmod 0400 ${drupal_root}/vendor/drush` with `vendor/drush -> /etc/cron.daily` removes
operator access while leaving directory content intact (potential operational DoS).

### Evidence
```
# line 110
[ -d "${drupal_root}" ] && chmod 02775 ${drupal_root}
# lines 113–117
if [ -d "${drupal_root}/web" ]; then
  chmod 02775 ${drupal_root}/web
elif [ -d "${drupal_root}/docroot" ]; then
  chmod 02775 ${drupal_root}/docroot
elif [ -d "${drupal_root}/html" ]; then
  chmod 02775 ${drupal_root}/html
fi
# lines 126–133
chmod 0644 ${drupal_root}/*.php
chmod 0664 ${drupal_root}/autoload.php
chmod 0751 ${drupal_root}/sites
chmod 0755 ${drupal_root}/sites/*
chmod 0644 ${drupal_root}/sites/*.php
...
# lines 139–141 (lock branch)
chmod 0400 ${drupal_root}/vendor/drush
chmod 0400 ${drupal_root}/vendor/symfony/console/Input
chmod 0400 ${drupal_root}/vendor/symfony/console/Style
# line 152
chmod 0644 ${drupal_root}/.htaccess
```

### Fix
Add `--no-dereference` (`-h`) to every direct chmod that operates on a glob-expanded or
caller-controlled path. Validate canonical path of `${drupal_root}` against an allowed
prefix. Optionally, refuse to operate if any of the named child paths
(`web`, `docroot`, `html`, `vendor`, `sites`, `.htaccess`, `*.php`) is a symlink.

Note: GNU chmod's `--no-dereference` exists but does not change the underlying
permission semantics of the target (chmod on a symlink itself is a no-op on Linux).
The effect is purely defensive: the call becomes a no-op for symlinks, removing the
attack surface.

### Patch commit
PATCHED in this commit. chown -L -R replaced with chown -h -R, every chown
on caller-controlled paths now uses -h, _validate_path_prefix added at
the top of the script (rejects anything that does not resolve under
/var/aegir/, /data/disk/, or /home/).

---

## [HIGH] chmod via symlink in lock-local-drush-permissions.sh
**File:** aegir/tools/bin/lock-local-drush-permissions.sh  (lines 57–64, 69–76)
**Category:** privilege-escalation
**Status:** PATCHED

### Description
Same NOPASSWD sudo entry point. `lock-local-drush-permissions.sh --root=... --mode=unlock`
runs `chmod 0775` on a caller-controlled path; with a `vendor/drush` symlink to a
sensitive file (e.g. `/etc/shadow`) the file becomes world-readable+executable.
With `--mode=lock` and `chmod 0400`, sensitive system files can be made unreadable to
their normal groups (operational impact).

There is also an additional argument-parsing bug: the case branch sets `mode="${1#*=}"`
(no underscore prefix) while the rest of the script reads `${mode}`/`${lock_mode}`
inconsistently — `lock_mode` is only initialised from positional `$2`, and `mode` is
the variable later checked. This is not security-relevant on its own but indicates the
caller-supplied `--mode=` value is honoured.

### Evidence
```
# lines 57–64 (vendor branch)
chmod 0775 ${drupal_root}/vendor/drush
chmod 0775 ${drupal_root}/vendor/symfony/console/Input
chmod 0775 ${drupal_root}/vendor/symfony/console/Style
...
chmod 0400 ${drupal_root}/vendor/drush
chmod 0400 ${drupal_root}/vendor/symfony/console/Input
chmod 0400 ${drupal_root}/vendor/symfony/console/Style
```

### Fix
Add `-h` to every chmod, or precheck `[ -L "${path}" ]` and refuse to operate on
symlinks. Validate canonical `${drupal_root}` against an expected prefix.

### Patch commit
PATCHED in this commit. Added _validate_path_prefix + _chmod_safe helpers;
every direct chmod now goes through _chmod_safe which skips symlinks.

---

## [MEDIUM] lshell `allowed_shell_escape` includes commands with built-in shell escape (mysql, tar, rsync, ssh)
**File:** aegir/tools/system/conf/lshell.conf  (line 55)
**Category:** privilege-escalation
**Status:** NEEDS-REVIEW

### Description
The lshell `allowed_shell_escape` list permits commands to spawn child processes
without the `sudo_noexec.so` LD_PRELOAD wrapper that would otherwise prevent shell
escapes. Several commands on the list have well-known interactive shell-escape syntaxes:

- `mysql` — the interactive client supports `\!` to run a shell command
  (`mysql -e '\! /bin/bash'`). Combined with the unrestricted aliasing of `env` to `true`
  the user transitions from the lshell session to a full bash shell as their own UID.
- `tar` — `tar -cf - --checkpoint=1 --checkpoint-action=exec=sh /tmp` runs an arbitrary
  command via the checkpoint action.
- `rsync` — `rsync -e 'sh -c "/bin/sh </dev/tty >/dev/tty 2>&1"' /tmp/ remote:` spawns
  a shell via the SSH-replacement option.
- `ssh` — `ssh -o ProxyCommand="/bin/sh" remote` or `ssh -o "PermitLocalCommand yes"
  -o "LocalCommand /bin/bash" remote` runs shell as the local user.
- `git` — `git -c core.editor=/bin/sh tag -a x` and similar config-driven editor hooks
  run an arbitrary editor; with `gitconfig` user-writable this is a reliable escape.
- `composer`, `npm`, `gem`, `bower`, `bundle`, `grunt`, `gulp` — execute arbitrary
  scripts from project metadata (composer scripts, npm lifecycle hooks, Rakefile, etc.).

For BOA's threat model the lshell user is **already** the file owner of the codebase
they operate on, so post-escape they can already do everything those project hooks would
allow. The real concern is lateral movement: any tool that yields an interactive shell
gives the user access to commands not in the lshell `allowed` list, and to anything
readable by their UID/GID (including other sites in `/var/www/`-style shared layouts and
any group memberships such as `users` or `www-data` accidentally added).

The mysql, tar, rsync, ssh items are the most clearly exploitable as
**confinement bypass** rather than just same-user code execution.

### Evidence
```
allowed_shell_escape : ['bower', 'bundle', 'bzip2', 'compass', 'composer', 'curl',
  'drush', 'drush10', 'drush11', 'drush8', 'env', ..., 'mysql', 'mysqldump', 'node',
  'npm', 'npx', 'mybackup', 'rsync', ..., 'ssh', 'tar', 'true', 'unzip', 'vdrush',
  'vendor/drush/drush/drush.php', 'zstd', '1']
```

### Fix
Per CLAUDE.md "When to Ask": **do not patch this without explicit confirmation.**
Each of these commands is on the list for a legitimate workflow reason (drush+rsync
deployments, mysql/mysqldump for site DB access, tar/zstd for archive creation,
git/composer/npm for codebase management). Removing any entry will break operator
workflows.

Recommended discussion items for Adam:
1. Is the lshell account intended to be a **same-UID confinement** layer (in which
   case these escapes are an explicit accepted risk), or a **hard sandbox** (in which
   case the bypassable entries should be removed or gated)?
2. If hard-sandbox intent: candidates for removal from `allowed_shell_escape`:
   `tar` (callers can use `bzip2`/`zstd` for non-checkpoint compression),
   `ssh`/`rsync` (limit to `overssh` for inbound only).
3. `mysql` interactive escape is mitigated by configuring `--disable-system-command`
   in user `~/.my.cnf` if available in the linked client; alternative is to provide
   a wrapper that strips `\!` lines from stdin. Worth a separate investigation.

### Patch commit
PENDING — awaiting Adam's intent decision.

---

## [MEDIUM] lshell `find` allowed without shell-escape relies on sudo_noexec.so autodetection
**File:** aegir/tools/system/conf/lshell.conf  (lines 27, 46)
**Category:** privilege-escalation
**Status:** NEEDS-REVIEW

### Description
`find` is in the `allowed` list (line 46) but not in `allowed_shell_escape`, which means
lshell wraps it via `LD_PRELOAD=/usr/libexec/sudo_noexec.so` to block `find -exec` from
spawning a shell. The `path_noexec` setting that points to the LD_PRELOAD object is
**commented out** (line 27). The lshell docs note that if `path_noexec` is unset, lshell
attempts auto-detection; if auto-detection fails, lshell logs a warning but still runs
commands — without the noexec wrapper, `find -exec /bin/sh \;` escapes immediately.

On Devuan Daedalus the sudo package ships `sudo_noexec.so` at a discoverable path
(`/usr/libexec/sudo/sudo_noexec.so` or `/usr/lib/sudo/sudo_noexec.so` depending on
build). If the sudo package is removed or the path changes in a future Debian/Devuan
release without BOA's lshell template being updated, the protection silently lapses.

### Evidence
```
# line 27 (commented out)
#path_noexec     : '/usr/libexec/sudo_noexec.so'
# line 46
allowed : [..., 'find', ...]
```

### Fix
Set `path_noexec` explicitly to the correct path for the target OS. Per lshell docs,
if the path is set and the object is not found, lshell exits immediately — fail-closed
rather than fail-open. Combine with a deployment check (in `manage_ltd_users.sh` or
`barracuda` install) that the configured path exists; abort install/update if not.

NEEDS-REVIEW: confirm the current path on Devuan Daedalus
(`dpkg -L sudo | grep noexec`) and whether it differs from Debian Bookworm. If it
differs, the template needs an OS branch.

### Patch commit
PENDING

---

## [LOW] lshell `scp` allowed; scp -S can run arbitrary binary
**File:** aegir/tools/system/conf/lshell.conf  (lines 46, 109)
**Category:** privilege-escalation
**Status:** NEEDS-REVIEW

### Description
`scp` accepts `-S program` to specify an alternate ssh transport program; the
specified path is exec'd by scp. From an lshell session,
`scp -S /tmp/myshell.sh foo remote:` runs `/tmp/myshell.sh` as the current user.
Mitigations: openssh 9.0+ defaults to `sftp` mode internally for new scp clients,
making `-S` less universally exploitable; this is a same-UID bypass, not a
cross-user escalation.

### Evidence
```
allowed : [..., 'scp', ...]
scp     : 1
```

### Fix
Same dependency as the broader `allowed_shell_escape` decision — see the
MEDIUM finding above. Requires Adam's intent decision before any change.

### Patch commit
PENDING

---

## [LOW] /etc/sudoers written without visudo validation; potential corruption on bad `_USER`
**File:** lib/functions/master.sh.inc:761,767,995; lib/functions/satellite.sh.inc:2869,2872,2878,2884; lib/functions/system.sh.inc:7774,7782,7796,7802; lib/functions/xtra.sh.inc:387,389
**Category:** privilege-escalation
**Status:** OPEN

### Description
Several call sites append directly to `/etc/sudoers` (or to per-script files in
`/etc/sudoers.d/`) using `echo ... >>`, with no `visudo -c -f` validation step. If
`${_USER}` or `${_HM_U}` ever contains whitespace, newline, or sudoers metacharacters
(`=`, `,`, `:`) the resulting line either fails to parse — breaking sudo entirely
until manually repaired — or, in the worst case, expands the effective rule. The
`_USER` value is set internally by Octopus scripts and is unlikely to be attacker-
controlled today, but the lack of validation is a fragile pattern.

Additionally, the INIT branch at `satellite.sh.inc:2869` unconditionally appends
the `${_USER} ALL=NOPASSWD: /etc/init.d/nginx` line without checking for duplicates,
so re-running INIT for the same `_USER` produces duplicate lines in `/etc/sudoers`.
This is hygiene, not a security bug, but worth noting.

### Evidence
```
# satellite.sh.inc:2869
echo "${_USER} ALL=NOPASSWD: /etc/init.d/nginx" >> /etc/sudoers
# (no visudo -c -f /etc/sudoers afterwards)
```

### Fix
Write the new rule to a per-script file under `/etc/sudoers.d/` (which is already
done for the helper scripts), validate with `visudo -c -f /etc/sudoers.d/<file>`
before chmod 0440, and bail with a clear error if validation fails. Eliminate
direct edits of `/etc/sudoers` entirely — every BOA-managed rule should live in
`/etc/sudoers.d/` so that the base `/etc/sudoers` file remains untouched.

For the INIT-branch duplicate-line bug: gate the append behind the same
`_VAR_IF_PRESENT` grep used in the non-INIT branch.

### Patch commit
PENDING

---

## [LOW] NOPASSWD sudo rule for `/etc/init.d/nginx` has no argument restriction
**File:** lib/functions/master.sh.inc:761; lib/functions/satellite.sh.inc:2869,2878; lib/functions/system.sh.inc:7774,7796
**Category:** privilege-escalation
**Status:** INFO

### Description
The sudoers rule `aegir ALL=NOPASSWD: /etc/init.d/nginx` allows aegir to invoke
`/etc/init.d/nginx` with **any arguments** as root. `/etc/init.d/nginx` is a sysv
init script (or systemd shim) accepting `start|stop|status|reload|restart|...`. The
script itself is root-owned (aegir cannot modify it), so the worst-case exposure is
invoking unintended verbs (`stop`, `restart`) — operational impact, not privilege
escalation. Worth noting because the same lack-of-arg-restriction pattern is
replicated to per-Octopus admins.

### Evidence
```
echo "aegir ALL=NOPASSWD: /etc/init.d/nginx" >> /etc/sudoers
```

### Fix
Optional hardening: change to
`aegir ALL=NOPASSWD: /etc/init.d/nginx reload, /etc/init.d/nginx start, /etc/init.d/nginx stop`
(explicitly enumerate allowed argument lists). Verify BOA's actual call patterns
first — `satellite.sh.inc:5923` uses `sudo /etc/init.d/nginx reload`.

### Patch commit
PENDING (deferred until intent confirmed)

---

## [INFO] /opt/user/{gems,npm} created mode 1777
**File:** aegir/tools/system/manage_ltd_users.sh:399,425
**Category:** privilege-escalation
**Status:** INFO

### Description
`/opt/user/gems` and `/opt/user/npm` are created world-writable with sticky bit
(mode 1777, same as `/tmp`). Per-user subdirectories under each are owned by the
respective limited user. The sticky bit prevents cross-user deletion, but any
local user (including www-data) can create new top-level entries under these paths.
This is intended (shared scratch for user-installed gems/npm packages) and
matches the `/tmp` model, but it is worth flagging that any file that a script
later looks up under `/opt/user/gems/<expected>` can be shadowed by a deliberately
placed entry of the same name if the lookup uses a non-existent username. No clear
exploit path observed.

### Evidence
```
chmod 1777 /opt/user/gems
chmod 1777 /opt/user/npm
```

### Fix
None recommended. Note that per-user subdirectories are chowned correctly and the
sticky bit prevents cross-user tampering. Document the choice in DECISIONS.md if
not already.

### Patch commit
N/A

---

# Patch confirmation — resolved before this commit

Adam confirmed the following on 2026-05-23 (also recorded in DECISIONS.md):

(a) Legitimate symlinks inside platforms exist only in legacy D6/D7 platforms
    where the **shared core is symlinked by BOA root / Aegir Provision**. End
    users have no write access to those paths and cannot create symlinks
    inside them. The realistic attack surface for end-user-planted symlinks is
    a tar archive uploaded into the user's own tree under
    `/data/disk/<u>/` or `/home/<u>/` — even php.ini protections may not be
    enough on their own.
    → Adopted defence: `chown -h` on every recursive/non-recursive chown
    (skips dereferencing without aborting on legacy root-managed symlinks),
    plus `_chmod_safe` (skip-on-symlink) on every direct chmod. Legacy
    layouts remain functional; attacker-planted symlinks are inert.

(b) Allowed roots are `/var/aegir/` (master, no end-user write), `/data/disk/`
    (per-Octopus admins), and `/home/` (limited users). No other roots.
    → Adopted: `realpath -e` prefix check matches these three.

(c) `allowed_shell_escape` stays as-is — the listed commands are required for
    codebase/site management. Node-related tools are intentionally not
    installed on multi-user systems (documented in BOA docs). Further
    hardening welcome where it does not break functionality. AppArmor
    profiles for multi-user hosts are noted as a future hardening target,
    not actioned in this audit.

See also: DECISIONS.md in the boa-security-audit project for the longer-form
rationale and deferred items.
