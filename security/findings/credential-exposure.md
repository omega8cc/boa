# Findings: Credential and Secret Handling

Covers credentials passed on the command line (visible in `/proc/PID/cmdline`),
credentials in logs / shell history, world- or group-readable secret files,
credentials passed via env to child processes (`/proc/PID/environ`),
temp files holding credentials, and dead-code credential reads that load
secrets into process memory for no reason.

Findings are appended below as they are discovered. Each entry follows the schema
defined in CLAUDE.md. Most-recent findings appear at the bottom.

---

## Audit scope coverage

- Every `mysql`/`mysqladmin`/`mysqldump`/`mydumper`/`mkpasswd`/`usermod -p`/`chpasswd`
  invocation in BOA scripts and libraries.
- All `/root/.my.*.txt` and `/root/.my.cnf` files, plus the per-tenant
  `/data/disk/<oct>/static/control/remote_backups/credentials/*.txt` files.
- `export FOO=...` of secret-bearing env vars and their /proc/environ visibility.
- The `/var/log/boa/aegir_install.log` OTLU pre-flagged in category 3.

Threat-model note: on Linux without `hidepid=2` on `/proc`, `/proc/PID/cmdline`
is world-readable. On a multi-user BOA host (multiple Octopus instances), one
tenant's `<user>.ftp` or system user can `ps -ef` other tenants' processes
and see their cmdline arguments — including `-p<password>` flags. This is
the recurring exposure class throughout this category.

---

## [MEDIUM] `mysql -p${_PROXYSQL_PASSWORD}` exposes ProxySQL admin password via /proc/PID/cmdline
**File:** lib/functions/master.sh.inc  (lines 260, 289, 331, 395, 499, 1124, 1158); lib/functions/satellite.sh.inc  (lines 2571, 2619, 2696, 2807); lib/functions/system.sh.inc  (lines 6725, 6726)
**Category:** credential-exposure
**Status:** PATCHED in follow-up commit

### Description
The ProxySQL admin password is loaded from `/root/.my.proxysql_adm_pwd.txt`
(0600 root) and then passed on the `mysql` command line as
`-p${_PROXYSQL_PASSWORD}`. The mysql binary's cmdline is in
`/proc/<mysql-pid>/cmdline`, which on Linux is world-readable by default
(no `hidepid` mount option set in BOA's `/etc/fstab` templates).

During the (brief but real) window each invocation is alive, any local
user on the host — including every BOA tenant's `<user>.ftp` and
per-Octopus system user `<user>` — can run `ps auxf` or
`cat /proc/<pid>/cmdline` and read the ProxySQL admin password.
On a multi-tenant host this is cross-tenant credential disclosure.

`system.sh.inc:6725-6726` is more exposed than the others:
```bash
mysql -uadmin -p`cat /root/.my.proxysql_adm_pwd.txt` -h127.0.0.1 -P6032 -e "SELECT * FROM scheduler\G"
```
The backtick expansion happens in the SHELL before mysql is invoked, so
the resulting `mysql` cmdline contains the literal cleartext password.

The 13 sites in master.sh.inc / satellite.sh.inc all share the same shape.

### Evidence
```bash
# master.sh.inc:260 (representative)
mysql -uadmin -p${_PROXYSQL_PASSWORD} -h127.0.0.1 -P6032 --protocol=tcp<<PROXYSQL
DELETE FROM mysql_users WHERE username='${_ADBU}';
...
PROXYSQL

# system.sh.inc:6725
mysql -uadmin -p`cat /root/.my.proxysql_adm_pwd.txt` -h127.0.0.1 -P6032 -e "SELECT * FROM scheduler\G"
```

### Fix
Two options. **Option A** is the standard MySQL pattern:

1. Generate a runtime cnf at `/root/.my.proxysql_adm.cnf` (mode 0600) once
   the proxysql password is set:
   ```
   [client]
   user=admin
   password="${_PROXYSQL_PASSWORD}"
   host=127.0.0.1
   port=6032
   protocol=tcp
   ```
2. Replace `mysql -uadmin -p${_PROXYSQL_PASSWORD} -h127.0.0.1 -P6032 --protocol=tcp` with
   `mysql --defaults-extra-file=/root/.my.proxysql_adm.cnf` at every site.

The cnf approach removes the password from /proc/cmdline entirely; the
mysql client reads the cnf at start-up and never re-exposes the password.

**Option B**: enable `hidepid=2` on the /proc mount in BOA's fstab
template. This closes the entire class of /proc/PID/cmdline cross-user
disclosure system-wide, not just for mysql, but breaks `ps` visibility
of other users' processes for non-root accounts — which may affect some
monitoring tools.

Recommend Option A for the targeted fix here, with Option B as a
separate workstream-class hardening discussion.

NEEDS-REVIEW: this touches central plumbing (master.sh.inc /
satellite.sh.inc are sourced by every install/upgrade) and 13+ sites.
Recommend bundling with the next master/satellite-touching change so
Tier-3 coverage applies. Asking before patching because misformatted
cnf can prevent proxysql admin access for live production traffic.

### Patch commit
PENDING — awaiting confirmation.

---

## [MEDIUM] `mkpasswd "${pwd}"` and `usermod -p $ph` expose ltd-user / FTP-user credentials via /proc/PID/cmdline
**File:** aegir/tools/system/manage_ltd_users.sh  (lines 717–719); lib/functions/satellite.sh.inc  (lines 3354–3357, 3631–3633)
**Category:** credential-exposure
**Status:** PATCHED in follow-up commit

### Description
Both ltd-user (`manage_ltd_users.sh`) and FTP-user (`satellite.sh.inc`)
account creation chains pass the new account's plaintext password as
a command-line argument to `mkpasswd`, then pass the resulting hash
as a command-line argument to `usermod -p`:

```bash
# manage_ltd_users.sh:717-719
ph=$(mkpasswd -m sha-512 "${_ESC_LUPASS}" \
  $(openssl rand -base64 16 | tr -d '+=' | head -c 16) 2>&1)
usermod -p $ph ${_usrLtd}
```

`mkpasswd "${_ESC_LUPASS}"` puts the plaintext password in
`/proc/<mkpasswd-pid>/cmdline`. `usermod -p $ph` puts the hash in
`/proc/<usermod-pid>/cmdline`. Both windows are short (sub-second) but
real, and an attacker who can race the creation (e.g. an existing
tenant on the same host running a watch-loop over `/proc/*/cmdline`)
captures the credential.

### Evidence
```bash
# manage_ltd_users.sh:717
ph=$(mkpasswd -m sha-512 "${_ESC_LUPASS}" \
  $(openssl rand -base64 16 | tr -d '+=' | head -c 16) 2>&1)
# line 719
usermod -p $ph ${_usrLtd}

# satellite.sh.inc:3354 / 3631 — same shape for ${_USERFTP}
```

### Fix
Switch to stdin-based forms that keep the secret out of the cmdline:

```bash
# generate hash via stdin
local _salt
_salt=$(openssl rand -base64 16 | tr -d '+=' | head -c 16)
ph=$(printf '%s' "${_ESC_LUPASS}" | mkpasswd -m sha-512 -s -S "${_salt}")
# set the hash on the account via stdin instead of cmdline
printf '%s:%s\n' "${_usrLtd}" "${ph}" | chpasswd -e
```

`mkpasswd -s` reads the password from stdin (Debian/Devuan whois
package's `mkpasswd`). `chpasswd -e` reads `user:hash` from stdin and
sets the encrypted hash on the account. Both keep the secret out of
argv.

NEEDS-REVIEW: this changes the user-creation chain that BOA has used
for years. Three call sites — `manage_ltd_users.sh:717-719` and two
mirrors in `satellite.sh.inc`. Recommend a single focused commit with
Tier-3 coverage so the new-user creation path can be smoke-tested on
a fresh BOA instance.

### Patch commit
PENDING — awaiting confirmation.

---

## [MEDIUM] `mydumper --password=...` and the cluster `_C_SQL="mysql --password=..."` template
**File:** aegir/tools/system/mysql_backup.sh  (line 249); aegir/tools/system/mysql_cluster_backup.sh  (lines 52, 132+ — many uses of `${_C_SQL}`)
**Category:** credential-exposure
**Status:** PATCHED in follow-up commit

### Description
`mysql_backup.sh:249` invokes `mydumper --password=${_SQL_PSWD}` on the
cmdline once per database backed up (the hourly mysql_backup cron
processes every tenant DB serially). Cross-tenant /proc/PID/cmdline
exposure as above.

`mysql_cluster_backup.sh:52` builds an interpolated command template:
```bash
_C_SQL="mysql --user=root --password=${_SQL_PSWD} --host=${_SQL_HOST} --port=${_SQL_PORT} --protocol=tcp"
```
Then uses it ~30 times via `${_C_SQL} ${_DB} ...`. Every one of those
invocations exposes the cluster root password.

### Fix
- `mydumper`: supports `--defaults-file=<cnf>` (since 0.10+). Move
  credentials to `/root/.my.mydumper.cnf` (0600) and pass
  `--defaults-file=/root/.my.mydumper.cnf` instead of `--password=`.
- `mysql_cluster_backup.sh`: same approach — generate
  `/root/.my.cluster_root.cnf` once and replace the `_C_SQL` template
  with `mysql --defaults-extra-file=/root/.my.cluster_root.cnf --host=...`.

NEEDS-REVIEW: bundles naturally with the proxysql `_PROXYSQL_PASSWORD`
fix above — same pattern, same risk class, same Tier-3 testing scope.
Recommend one commit covering all three (proxysql admin, mydumper,
cluster root).

### Patch commit
PENDING — awaiting confirmation.

---

## [MEDIUM] `/var/log/boa/aegir_install.log` file mode 0644 — OTLU readable by any local user
**File:** lib/functions/master.sh.inc  (lines 1218–1219, 1226, 1232)
**Category:** credential-exposure (pre-flagged from category 3)
**Status:** PATCHED in this commit

### Description
The Aegir install log captures the one-time-login URL (OTLU) printed by
the Hostmaster install. master.sh.inc:1423 later extracts the URL from
this log to print/use it. The log is:
```bash
touch /var/log/boa/aegir_install.log              # creator default = 0644 root
chown aegir:aegir /var/log/boa/aegir_install.log  # mode unchanged
```
Mode 0644 means every local user (every BOA tenant) can read the log
and race the admin to the OTLU within its lifetime.

The OTLU is single-use and short-lived (Drupal user.module default is
24 hours, BOA install path may shorten it), but the window is real.
Any tenant who can read it and redeems it first becomes the Hostmaster
admin.

### Evidence
```bash
# master.sh.inc:1218-1219
touch /var/log/boa/aegir_install.log
chown aegir:aegir /var/log/boa/aegir_install.log
# ... 7 lines later ...
# master.sh.inc:1226
... 2>&1 | tee /var/log/boa/aegir_install.log
```

### Fix
Add `chmod 0600 /var/log/boa/aegir_install.log` immediately after the
`chown aegir:aegir` line. The file is then only readable by aegir +
root, both of which are already privileged.

### Patch commit
PATCHED — see commit message below.

---

## [LOW] `checksql.pl` reads MySQL root password into Perl memory but never uses it (pre-flagged from category 2)
**File:** aegir/tools/system/checksql.pl  (lines 26–27)
**Category:** credential-exposure
**Status:** PATCHED in this commit

### Description
```perl
$mysqlrootpass=`cat /root/.my.pass.txt`;
chomp($mysqlrootpass);
```
The variable is never referenced afterwards. `mysqlcheck` (line 28)
takes credentials from `/root/.my.cnf` implicitly. The read is dead
code that loads the plaintext root password into the Perl interpreter's
process memory (and any future core dump) for nothing.

### Fix
Delete both lines.

### Patch commit
PATCHED — see commit message below.

---

## [LOW] Dead `_SQL_PSWD=$(cat /root/.my.pass.txt)` reads in cron scripts
**File:** BOA.sh.txt:944; aegir/tools/system/move_sql.sh:143; aegir/tools/system/mysql_repair.sh:55
**Category:** credential-exposure
**Status:** PATCHED in this commit

### Description
Three sites read `_SQL_PSWD` from `/root/.my.pass.txt` but never
reference the variable afterwards. The surrounding mysql/mysqlcheck
calls use `-u root` only, which makes the mysql client read
`/root/.my.cnf` for the password implicitly. The shell-variable
copy is dead.

`aegir/tools/system/monitor/check/mysql.sh:172` reads `_SQL_PSWD` too
but uses it only as a non-empty proxy for "is the file present and
non-empty" (`[ ! -z "${_SQL_PSWD}" ]`). That can be replaced with
`[ -s /root/.my.pass.txt ]`, which avoids loading the cleartext into
shell memory.

### Fix
- BOA.sh.txt:944 — delete the line.
- move_sql.sh:143 — delete the line.
- mysql_repair.sh:55 — delete the line.
- monitor/check/mysql.sh:172/174 — change the read to a file-existence
  check.

### Patch commit
PATCHED — see commit message below.

---

## [LOW] duplicity `_BACKUP_TARGET` URL embeds cloud-storage KEY:SECRET in /proc/PID/cmdline
**File:** aegir/tools/backup/run/duplicity_backup.sh  (lines 925, 935, 940, 945)
**Category:** credential-exposure
**Status:** PATCHED in follow-up commit (5 of 6 providers); ibm residual

### Description
For S3-compatible providers, BOA constructs the `_BACKUP_TARGET` URL
as `s3://KEY:SECRET@region/bucket` and passes it as a cmdline argument
to duplicity. The whole URL — including the access key and secret —
appears in `/proc/<duplicity-pid>/cmdline` for the duration of the
backup (typically tens of minutes to hours).

On a multi-tenant host one tenant's lshell-allowed `ps` invocation
sees the other tenants' duplicity cmdlines (each running as its own
per-tenant system user, but all visible via /proc).

Affected providers in the codebase: AWS S3, R2 (Cloudflare),
DigitalOcean Spaces, Linode, Wasabi, IBM COS. The `gcs://` form
(GCS) does not embed credentials in the URL — that one is safe.

### Evidence
```bash
# duplicity_backup.sh:925
export _BACKUP_TARGET="s3://${DO_SPACES_KEY}:${DO_SPACES_SECRET}@${DO_SPACES_REGION}/${_BUCKET_NAME}"
# line 935
export _BACKUP_TARGET="ibmcos://${IBM_API_KEY_ID}:${IBM_SERVICE_INSTANCE_ID}@${IBM_REGION}/${_BUCKET_NAME}"
# line 940
export _BACKUP_TARGET="s3://${LINODE_ACCESS_KEY}:${LINODE_SECRET_KEY}@${LINODE_REGION}/${_BUCKET_NAME}"
# line 945
export _BACKUP_TARGET="s3://${WASABI_ACCESS_KEY}:${WASABI_SECRET_KEY}@${WASABI_REGION}/${_BUCKET_NAME}"
```

### Fix
Use the env-var form duplicity supports for S3-compatible providers:
```bash
export AWS_ACCESS_KEY_ID="${KEY}"
export AWS_SECRET_ACCESS_KEY="${SECRET}"
export _BACKUP_TARGET="s3://${HOST}/${_BUCKET_NAME}"
```
`/proc/PID/environ` is owner-only readable on Linux by default
(unlike `/proc/PID/cmdline` which is world-readable). Each provider
has its own env-var naming convention — duplicity respects the
boto3-style `AWS_*` for the s3 backend and provider-specific ones
elsewhere.

NEEDS-REVIEW: provider-by-provider refactor; each backend has its
own credential-env-var convention. Recommend scheduling against
boa-modernisation alongside the broader `mybackup` rewrite items.

### Patch commit
PENDING — deferred to boa-modernisation.

---

## [LOW] No `hidepid=2` on `/proc` mount — Linux defaults expose all PID cmdlines cross-user
**File:** (no fstab template touches /proc in the repo; mentioned for completeness)
**Category:** credential-exposure
**Status:** PATCHED in follow-up commit

### Description
On a multi-tenant BOA host, the `/proc/PID/cmdline` exposure of `-p<pwd>`
flags, embedded URLs, and other cmdline-credential sites depends on
`/proc` being mounted with default options. Linux supports
`hidepid=2` (and the matching `gid=` option) on procfs to restrict
non-root users to seeing only their own processes — closing the entire
class of /proc/cmdline cross-user disclosures with one mount option.

Implementation:
```
# /etc/fstab
proc  /proc  proc  defaults,hidepid=2,gid=adm  0  0
```
Members of the `adm` group (typically monitoring tools, log-shipping
agents) retain visibility; everyone else sees only their own processes.

Tradeoffs:
- Breaks `ps -ef` showing other users' processes for non-root accounts.
  Some BOA tools may rely on this (e.g., the legacy `proc_num_ctrl.pl`
  monitor — though that runs as root). Worth checking the lshell
  `allowed` command set for any tool that `ps -ef`s and expects to see
  more than its own processes.
- `pgrep -f` from non-root users would only match own processes.
- Containers / LXC may need separate handling.

### Fix
Not actioned in this audit. Recommended as a system-level hardening
discussion separate from the per-script credential patches above. If
adopted, several of the MEDIUM findings here drop to LOW or INFO
automatically.

### Patch commit
N/A.

---

## [INFO] duplicity `PASSPHRASE` env export is /proc/environ-readable but Linux defaults restrict to owner
**File:** aegir/tools/backup/run/duplicity_backup.sh  (line 392)
**Category:** credential-exposure
**Status:** INFO — verified acceptable

### Description
```bash
export PASSPHRASE=$(cat "${_secret_file}")
```
Sets the duplicity encryption passphrase as an env var. Inherited by
duplicity. Visible in `/proc/<duplicity-pid>/environ`, but on Linux
that file is mode 0400 owner-only by default — only the process owner
and root can read it. On a multi-tenant host one tenant cannot read
another tenant's PASSPHRASE.

Use of env var is the standard duplicity-recommended pattern; the
alternative (cmdline `--passphrase=` flag) would be strictly worse
since /proc/PID/cmdline is world-readable.

### Fix
N/A — acceptable as-is.

### Patch commit
N/A.

---

## [HIGH-from-cat-5] SQL identifier injection in mysql_backup.sh and mysql_cluster_backup.sh (carry-over from category 5)
**File:** aegir/tools/system/mysql_backup.sh  (lines 152, 163, 173, 183, 193, 203, 207, 270, 290+); aegir/tools/system/mysql_cluster_backup.sh  (lines 142, 153, 163, 173, 183, 193, 197)
**Category:** carry-over from shell-injection (category 5)
**Status:** PATCHED in this commit

### Description
Category 5 patched `mysql_cleanup.sh` for the cross-tenant `DROP DATABASE`
risk via tenant-crafted table names containing backticks. The same
pattern exists in two other cron-driven scripts:

- `mysql_backup.sh` — hourly truncate of cache/watchdog/accesslog/batch/queue
  tables before backup. Same six `for X in ${_TABLES}; do mysql ${_DB}<<EOF
  TRUNCATE ${X}; EOF; done` loops.
- `mysql_cluster_backup.sh` — same shape, executed via `${_C_SQL} ${_DB}<<EOF`
  (the `_C_SQL` template that also has the `--password=` exposure flagged above).

The category-5 audit only searched in `mysql_cleanup.sh` and missed both
mirrors. Surfacing now and applying the same fix: `_is_safe_ident`
allowlist + backtick-quoting.

### Fix
Add `_is_safe_ident` helper at the top of each file. Gate every
TRUNCATE/DROP loop with `if ! _is_safe_ident "${X}"; then continue; fi`.
Backtick-quote every identifier in the SQL heredocs.

### Patch commit
PATCHED — see commit message below.
