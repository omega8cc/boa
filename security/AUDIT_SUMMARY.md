# BOA Security Audit — Summary

Quick-reference summary of the 8-category audit completed on `security-audit`
branch. Read this first; dive into `security/findings/<category>.md` for
per-finding details and `~/projects/boa-security-audit/DECISIONS.md` for the
full decision log including the rationale behind each defer / patch choice.

This file is the **stable hand-off doc** between audit sessions — the
findings files are organised by category and the commit messages contain
per-change rationale, but this file captures the things that are easiest to
lose between sessions: the Tier-3 verification matrix, the threat-class →
commit map, and the punch-list of operator-pending decisions.

---

## Commits landed on security-audit

```
9853f6eab  cat 8  misc sweep complete -- no new patches needed
e9451c3c6  cat 7  PHP / Nginx / MySQL / SSH / sysctl hardening
786849236  cat 6  BOA PI mode -- full /proc cmdline credential closure
8dc47dbff  cat 6  OTLU mode, dead pwd reads, cat-5 SQL-ident carry-over
fbdfc862d  cat 5  HTTPS mirrors + cert-validate + mysql_cleanup ident allowlist
dc1878958  cat 5  document HTTP-mirror MITM and SQL-identifier injection
ab01133e5  cat 4  close mybackup queue-file injection (.ftp -> sysuser)
e3614cacd  cat 4  lock.inc auto-fd via brace expansion, drop eval
33394aa50  cat 3  /opt/tmp scratch root uses sticky 1777
d11d7c99c  cat 3  daily.sh chown -L symlink path + 0777 dir tightening
e6a267e83  cat 2  scan_nginx UA filter + IP validation tightening
65c2b8e28  cat 1  block tar-symlink to root via NOPASSWD-sudo helpers
176c6136c  cat 0  initialise audit findings scaffolding (pre-existing)
```

---

## Threat class → commit map

| Threat class | Closure | Commit |
|---|---|---|
| aegir → root via tar-symlink in NOPASSWD sudo helpers | `chown -h` + realpath prefix check | `65c2b8e28` |
| Cron `daily.sh` chown -L symlink follow | `chown -h` + `_validate_safe_dir` | `d11d7c99c` |
| `.ftp` → system user via mybackup queue-file shell injection | mapfile + positional `su -c` + `_validate_restore_command` whitespace forbid | `ab01133e5` |
| Network-MITM → root via plain-HTTP BOA mirror | https:// flip + `-k` / `--no-check-certificate` removal | `fbdfc862d` |
| Cross-tenant `DROP DATABASE` via tenant-named tables with backticks | `_is_safe_ident` allowlist + identifier backtick-quoting in cleanup, backup, cluster-backup | `fbdfc862d` + `8dc47dbff` |
| Cross-tenant `/proc/PID/cmdline` credential disclosure | `hidepid=2,gid=adm` + 4-area cleartext-cmdline refactor (proxysql, mkpasswd, mydumper, duplicity) | `786849236` |
| Aegir OTLU world-readable in install log | `chmod 0600` after chown aegir:aegir | `8dc47dbff` |
| `/opt/tmp` BOA scratch world-writable without sticky bit | `chmod 1777` instead of `-R 777` | `33394aa50` |
| `/var/tmp/fpm` opcache lockfile cross-tenant deletion | `chmod 1777` (sticky) | `d11d7c99c` |
| `/var/log/php*` cross-tenant pool enumeration | `chmod 0755 root:adm` | `d11d7c99c` |
| `scan_nginx.sh` UA terminal-escape & loose IP validation | `${_UA//[^[:print:][:space:]]/?}` + `_validate_ip` gate | `e6a267e83` |
| `lock.inc` eval-based fd allocation | bash `exec {var}>...` auto-fd | `e3614cacd` |
| Dead MySQL root password reads dragging pwd into process memory | Removed `_SQL_PSWD=$(cat /root/.my.pass.txt)` in 4 sites | `8dc47dbff` |
| PHP version disclosure / session-fixation / SameSite empty | 24 PHP ini templates: `expose_php Off`, `session.use_strict_mode 1`, `session.cookie_samesite Lax` | `e9451c3c6` |
| Nginx version disclosure | `server_tokens off` in http{} | `e9451c3c6` |
| MySQL `LOAD DATA LOCAL INFILE` on Percona 5.7 | `local_infile = OFF` in my.cnf.txt | `e9451c3c6` |
| SSH idle session never disconnects (~34 days) | `ClientAliveCountMax 10000` → `3` (~15 min) | `e9451c3c6` |
| Kernel eBPF / userfaultfd CVE classes for non-root | sysctl + 3 hardening knobs | `e9451c3c6` |

---

## Tier-3 verification matrix (boa-testing checklist)

When you cut a fresh BOA install on Devuan Daedalus from a `security-audit`-merged tree, verify these scenarios pass before merging to public branches:

| # | Scenario | What to confirm |
|---|---|---|
| 1 | Fresh `barracuda install dev` from patched mirror | HTTPS fetch works end-to-end; no `-k` regressions; every fetched binary chmod'd 700 / chown'd root |
| 2 | ProxySQL admin operations | `mysql --defaults-extra-file=/root/.my.proxysql_adm.cnf` connects and runs INSERT/UPDATE; cnf is 0600 root:root |
| 3 | Limited-user creation via `manage_ltd_users.sh` | New `.ftp` account created; SFTP login + lshell session work; password never appears in `/proc/PID/cmdline` during the create window |
| 4 | mysql cluster backup on a real Galera cluster | `mydumper` / `mysqldump` / `mysqlcheck` all succeed via `--defaults-extra-file=/root/.my.cluster_root.cnf`; localhost-vs-cluster password consistency verified (see DECISIONS.md cat-6 open question) |
| 5 | Each cloud-storage provider for `mybackup` | Backup-restore round-trip for cloudflare/R2, do_spaces, linode, wasabi, b2; verify AWS_ACCESS_KEY_ID / B2_APPLICATION_KEY env exports reach duplicity; ibmcos residual exposure noted |
| 6 | `/proc/PID/cmdline` cross-tenant invisibility | From `<user>.ftp` lshell session (after the escape vectors documented in cat 1 are tested), `ps -ef` shows only own processes; `cat /proc/<other-uid-pid>/cmdline` returns no data |
| 7 | `hidepid=2` survives reboot | `/etc/fstab` has the `proc /proc proc defaults,hidepid=2,gid=<adm-gid>` line; reboot → `/proc/mounts` still shows hidepid=2 |
| 8 | PHP 8.x session behaviour | Drupal 10+, Hostmaster, and any tenant-supplied contrib modules behave correctly under `session.use_strict_mode = 1` and `cookie_samesite = Lax`; no login regressions |
| 9 | SSH session hardening | `ClientAliveCountMax 3` doesn't break legitimate long-idle workflows (e.g. tmux/screen with active rsync running); `MaxAuthTries 3` doesn't lock out legitimate password operators |
| 10 | sysctl eBPF/userfaultfd hardening | collectd / Munin / any monitoring agents that touch eBPF or userfaultfd continue to function; `kernel.unprivileged_bpf_disabled=1` doesn't break root-context bpftrace if you use it |
| 11 | mybackup queue-file rejection | Crafted queue-file with whitespace in `_restore_path` is logged to `/var/log/mybackup_invalid_queued.log` and removed without execution |
| 12 | Mysql identifier allowlist | Create a tenant DB, create a table with a backtick in its name (e.g. via raw INSERT into mysql.tables_priv), confirm `mysql_cleanup.sh` skips it with a WARN log line |

---

## Pending operator decisions (punch-list, NOT blocking close)

Items the audit identified but deferred for operator judgment. Each is a small focused commit when you're ready.

### lshell layer
- **`path_noexec` explicit path** (cat 1, cat 7 carry-over) — needs `dpkg -L sudo | grep noexec` on Devuan Daedalus to set the right path. One-line `lshell.conf` change.
- **`allowed_shell_escape` re-evaluation** — only revisit if BOA ever moves toward hard-sandbox lshell intent (currently same-UID confinement per cat-1 confirmation).

### Config templates (cat 7)
- **ImageMagick policy.xml** — tighten URL/HTTP/HTTPS delegates and uncomment the PS/PDF/EPS/XPS coder restrictions. Trade-off with Drupal contrib modules that legitimately need PDF rendering / URL fetching.
- **MySQL `bind-address`** — conditional template substitute based on `_CLUSTER` flag. Would bind to 127.0.0.1 on standalone, omit on cluster.
- **SSH `PasswordAuthentication no`** — with `Match Group lshellg` overlay so lshell-restricted operators can still password-auth. Standard hardening; needs verification that no operator workflow breaks.

### Workstream-sized refactors (cat 2, cat 3)
- **`daily.sh` broader chown/chmod sweep** (cat 3 MEDIUM) — ~50 chown/chmod lines on `${_Dir}` / `${_Plr}` paths without `-h` / `[ ! -L ]` prechecks. Path-prefix validator already lands worst-case; this is the residual single-file blast surface. Bundle with the same refactor for `manage_ltd_users.sh`'s per-tenant chown loops.
- **`segfault_alert.pl` rewrite to bash** (cat 2 MEDIUM) — defense-by-coincidence pattern (multiple log-derived variables interpolated into Perl backticks; safe today only because each upstream sanitiser holds). The file already has a `TODO - rewrite this legacy script in bash` comment. Schedule against `boa-modernisation`.

### Residual LOW items
- **duplicity ibmcos URL credential** (cat 6 LOW) — ibmcos backend has no env-var alternative to the in-URL credential form. Tracked as residual; needs upstream duplicity-ibmcos support or backend replacement.
- **Node `curl https://...nodesource.com | sudo bash -`** (cat 8 LOW) — runs only on single-tenant hosts per BOA's no-Node-on-multi-tenant policy. Replace with manual apt-repo + GPG-key pin when xtra.sh.inc next gets touched.
- **`/tmp/virtwhat.$$.strace`** (cat 3 / cat 8 LOW) — predictable filename. Install-time only, no untrusted users present. One-line `mktemp` change.
- **`find … | xargs rm -f`** (cat 5 LOW) — fragile to whitespace in filenames. Convert to `find … -delete` or `find … -exec rm -f {} +`. Bundle with the boa-modernisation `find` normalisation pass.

### One open verification question
- **mysql_cluster_backup.sh mydumper localhost-vs-cluster password consistency** (cat 6) — pre-refactor used `_SQL_PSWD` (cluster root password) against `--host=localhost`. The new `--defaults-file=/root/.my.cluster_root.cnf` has `host=${_SQL_HOST}` (cluster host, not localhost). If local mysql and cluster mysql ever have *different* root passwords on the same node, mydumper to localhost would fail auth. Likely fine in BOA practice (single root password across all cluster nodes) but flagged.

### Cleanup commits (separate from the audit, operator-curated)
- **Remove the three dead Perl monitors** (cat 2 INFO) — `hackcheck.pl`, `hackftp.pl`, `escapecheck.pl`. Already superseded by `.sh` siblings; not fetched by `BOA.sh.txt` on install. Pure-removal commit reviewed by Adam.
- **`/etc/sudoers` direct writes** (cat 1 LOW) — `lib/functions/{master,satellite,system,xtra}.sh.inc` write directly to `/etc/sudoers` without `visudo -c` validation. Bundle into a sudoers-write hygiene pass during boa-control-refactor or boa-modernisation.

---

## Audit posture notes

- **Push to `omm/private-dev` is the operator's call** per CLAUDE.md. Audit work was committed locally; nothing pushed.
- **`security-audit` branch tracks `omm/private-dev`** per the audit spec; merging back is via the standard BOA workflow.
- **Adam confirmed BOA PI (paranoid idiosyncrasies) mode** as the preferred posture in cat 6 — that's why this audit pass landed more layered hardening than the strict minimum.
- **The 8-category audit structure held up well** — every actionable finding fit cleanly into one of the categories. Cat 8 turned up zero new patches because the prior seven categories caught everything.

---

## How to resume audit work after a gap

1. Read this file first (you're doing it).
2. Read `~/projects/boa-security-audit/DECISIONS.md` for the per-decision rationale.
3. `git log --oneline security-audit` to see the patch history.
4. For any pending punch-list item: open the relevant `security/findings/<category>.md`, find the finding entry, follow the Fix section.
5. `git status` should be clean. If not, something is mid-flight from a prior session and needs reconciliation before new work.
