# Testing the Drush `*.drush.inc` backend loading filter

Verification runbook for the BOA hardening that stops Drush from loading
contributed-module `*.drush.inc` command files as the privileged Ægir backend user
(upstream issue [#762138](https://www.drupal.org/project/provision/issues/762138)).
The mechanics and the operator control files are documented in
[SECURITY.md](SECURITY.md); the client-side behaviour in [DRUSH-CLI.md](DRUSH-CLI.md).
This runbook confirms both required properties on a real box:

1. **Protection still works** — an Ægir backend identity (`aegir` / `oN`) refuses to
   load a tenant `*.drush.inc`.
2. **Limited-shell CLI is unaffected** — a client running Drush as their own
   `oN.ftp` account loads their site's contributed commands normally.

The filter keys on the process's **effective uid**, not the login shell, so both
tests below are faithful regardless of how the command is launched (the client's
real `oN.ftp` limited shell and a `su -s /bin/bash - oN.ftp` used here for easy
quoting behave identically).

## Conventions

Run everything as **root**. Substitute your real values in every snippet below,
including inside the here-documents:

- `<OCT>` — the Octopus instance user (for example `o1`)
- `<OCT>.ftp` — its limited-shell user (for example `o1.ftp`)
- `<SITE>` — a Drush 8 site alias on that instance (for example `@mysite.com`)

## Preconditions

Confirm a clean default state — no opt-in or global-disable control files skewing the
result:

```bash
ls -1 /data/conf/drush_extension_filter_disabled.txt \
      /data/conf/<OCT>_civicrm.txt /data/conf/<OCT>_elysia_cron.txt 2>/dev/null
```

- [ ] No output. If any of these exist and you want the strict default test, move them aside for the duration of the run.

## Test 1 — Direct decision check (definitive, no side effects)

Ask the deployed filter itself, inside each identity's live Drush process, what it
decides. This bypasses all bootstrap and discovery nuance.

```bash
cat > /tmp/boa_check.php <<'PHP'
<?php
// Run via: drush php-script /tmp/boa_check.php  (drush has already loaded the filter)
$tenant  = '/data/disk/<OCT>/distro/probe/sites/all/drush/evil.drush.inc'; // tenant path -> DENY for backend
$boatool = '/data/disk/<OCT>/.drush/sys/provision/provision.drush.inc';    // BOA-managed -> ALLOW for everyone
drush_print('patched           = ' . (function_exists('boa_drush_extension_backend_identity') ? 'yes' : 'NO -- OLD DRUSH STILL ACTIVE'));
drush_print('euid              = ' . posix_geteuid());
drush_print('backend_identity  = ' . var_export(boa_drush_extension_backend_identity(), true));
drush_print('allowed(tenant)   = ' . var_export(boa_drush_extension_allowed($tenant), true));
drush_print('allowed(BOA-tool) = ' . var_export(boa_drush_extension_allowed($boatool), true));
PHP

echo "--- as <OCT> (Ægir backend identity) ---"
su - <OCT> -c "drush php-script /tmp/boa_check.php"

echo "--- as <OCT>.ftp (limited shell) ---"
su -s /bin/bash - <OCT>.ftp -c "drush php-script /tmp/boa_check.php"
```

Expected as `<OCT>` (backend identity):

- [ ] `patched = yes`
- [ ] `backend_identity = true`
- [ ] `allowed(tenant) = false` — tenant `*.drush.inc` denied to the backend (#762138 held)
- [ ] `allowed(BOA-tool) = true` — BOA's own extensions still load (no over-block)

Expected as `<OCT>.ftp` (limited shell):

- [ ] `patched = yes`
- [ ] `backend_identity = false`
- [ ] `allowed(tenant) = true` — the client's own CLI is not filtered
- [ ] `allowed(BOA-tool) = true`

A `patched = NO` line means that identity is still running an un-patched Drush — fix
the install location before continuing.

## Test 2 — End-to-end through Drush's real discovery pipeline

Plant one harmless command file in a genuinely tenant-writable path, then watch the
**same file** get denied to the backend and loaded for the client. Its top-level line
writes a marker only when Drush actually loads the file, so the marker is ground
truth.

```bash
# Locate the Drupal root (must sit under /data/disk/<OCT>/{distro,static,platforms}/…)
ROOT=$(su - <OCT> -c "drush <SITE> dd" 2>/dev/null); echo "ROOT=$ROOT"
# (fallback if 'dd' is unavailable: drush <SITE> status --fields=root --format=list)

mkdir -p "$ROOT/sites/all/drush"
cat > "$ROOT/sites/all/drush/bprobe.drush.inc" <<'PHP'
<?php
// Harmless BOA filter probe — remove after testing.
@file_put_contents('/tmp/boa_probe_uid_' . posix_geteuid() . '.marker', date('c')."\n", FILE_APPEND);
function bprobe_drush_command() {
  return array('bprobe' => array('description' => 'BOA filter probe (harmless).',
                                  'bootstrap' => DRUSH_BOOTSTRAP_DRUSH));
}
function drush_bprobe() { drush_print('BOA-PROBE-RAN uid=' . posix_geteuid()); }
PHP
chown <OCT>:users "$ROOT/sites/all/drush/bprobe.drush.inc"
chmod 644 "$ROOT/sites/all/drush/bprobe.drush.inc"
```

### 2a — the backend must NOT see it

```bash
rm -f /tmp/boa_probe_uid_*.marker
su - <OCT> -c "drush <SITE> cc drush >/dev/null 2>&1; drush <SITE> bprobe; echo EXIT=\$?"
ls /tmp/boa_probe_uid_$(id -u <OCT>).marker 2>/dev/null && echo "MARKER PRESENT (BAD)" || echo "no marker (GOOD)"
```

- [ ] `drush <SITE> bprobe` reports the command is not found (non-zero EXIT)
- [ ] `no marker (GOOD)` — the backend neither ran nor loaded the tenant file

### 2b — the limited shell MUST see it

```bash
rm -f /tmp/boa_probe_uid_*.marker
su -s /bin/bash - <OCT>.ftp -c "drush <SITE> cc drush >/dev/null 2>&1; drush <SITE> bprobe; echo EXIT=\$?"
ls /tmp/boa_probe_uid_$(id -u <OCT>.ftp).marker 2>/dev/null && echo "MARKER PRESENT (GOOD)" || echo "no marker (BAD)"
```

- [ ] Prints `BOA-PROBE-RAN uid=<the .ftp uid>` (EXIT=0)
- [ ] `MARKER PRESENT (GOOD)` — the client's own contributed command loads and runs

This is exactly the reporter's `elysia-cron` situation: a contributed command file
that the client runs from their own `oN.ftp` shell.

## Test 3 — (optional) confirm via a real Ægir task

Proves the actual backend queue path — not just `su - <OCT>` — is protected. With the
probe still planted:

```bash
rm -f /tmp/boa_probe_uid_*.marker
# Run a Verify on the site or its platform from the Ægir control panel, or:
#   su - <OCT> -c "drush @hostmaster hosting-task <SITE> verify -y"
ls /tmp/boa_probe_uid_$(id -u <OCT>).marker 2>/dev/null && echo "BACKEND LOADED IT (BAD)" || echo "backend did not load it (GOOD)"
```

- [ ] The task completes normally
- [ ] `backend did not load it (GOOD)`

## Cleanup

```bash
rm -f "$ROOT/sites/all/drush/bprobe.drush.inc"
rmdir "$ROOT/sites/all/drush" 2>/dev/null   # removes it only if we created it and it is now empty
rm -f /tmp/boa_probe_uid_*.marker /tmp/boa_check.php
su - <OCT> -c "drush <SITE> cc drush >/dev/null 2>&1"
```

## Pass criteria

| # | Property | Signal |
|---|---|---|
| 1 | Protection still works | Test 1 as `<OCT>`: `allowed(tenant)=false`; Test 2a: `bprobe` not found and no marker; Test 3: no backend marker |
| 2 | Limited-shell CLI unaffected | Test 1 as `<OCT>.ftp`: `allowed(tenant)=true`; Test 2b: `BOA-PROBE-RAN` and marker present |
| — | No over-block / patch active | Both identities: `patched=yes` and `allowed(BOA-tool)=true` |
