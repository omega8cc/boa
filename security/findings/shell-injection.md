# Findings: Shell Injection (General)

Covers dynamic command construction from unvalidated input, unsafe wget/curl
URL building, find -exec / xargs patterns, heredoc payloads with attacker-
influenced variables, and pipe chains feeding into command args.

Findings are appended below as they are discovered. Each entry follows the schema
defined in CLAUDE.md. Most-recent findings appear at the bottom.

---

## Audit scope coverage

- Every `curl`/`wget` URL built from variables.
- All mysql heredoc payloads with interpolated identifiers.
- `find -exec` and `xargs` patterns.
- `for X in $(...)` and `for X in \`...\`` loops over external output.
- mybackup queue file (covered in category 4, fix landed).

---

## [HIGH] BOA install/upgrade fetches every binary over plain HTTP from mirror; curl uses `-k` (insecure)
**File:** BOA.sh.txt  (lines 67, 313, 314, 419, 4849, 5084) — and ~20 other files across BOA
**Category:** shell-injection (delivery-channel / MITM)
**Status:** PATCHED in follow-up commit

### Description
Every `curl ${_crlGet} "${_urlHmr}/..." -o /opt/local/bin/...` fetch in
the BOA installer/upgrader retrieves scripts over **plain HTTP**:

```bash
# BOA.sh.txt:67
_crlGet="-L --max-redirs 3 -k -s --retry 9 --retry-delay 9 -A iCab"
# BOA.sh.txt:313–314, 419
_urlDev="http://${_USE_MIR}/dev"
_urlHmr="http://${_USE_MIR}/versions/${_tRee}/boa/aegir"
_urlEnc="http://${_USE_MIR}/enc/2024"
```

`_USE_MIR` resolves to one of BOA's own mirrors (default `files.aegir.cc`)
via the `ffmirror` fastest-mirror selector. The mirror hostnames are
trusted. The protocol is not.

The downloaded files are then chmod'd 700 and chown'd root, then
executed/sourced. Every `curl ${_crlGet} "${_urlHmr}/tools/bin/<binary>"
-o /opt/local/bin/<binary>` followed by `chmod 700` / `chown root` is a
straight install of attacker code if the mirror traffic is MITM'd at
any point on the network path.

Compounding factors:
- `_crlGet` includes `-k` (`--insecure`), which disables certificate
  validation. Even if a future change switched the URL prefix to
  `https://`, `-k` would still accept any cert.
- There is no signature verification anywhere in the fetch chain. The
  one place with `sha256sum -c` (`system.sh.inc:8038`) is the Amazon
  Corretto Java install fetched from `https://corretto.aws/`, where the
  SHA comes from the same HTTPS host — outside-of-band verification
  only, not a BOA-managed key.

This is the classic supply-chain MITM exposure for distro-hosted scripts.
Severity HIGH: any attacker between the BOA install host and the BOA
mirror (rogue Wi-Fi, ISP, hop-on-path, compromised CDN edge, DNS spoof)
can substitute every BOA binary on the host — including the cron-driven
monitors that run as root.

### Evidence
```bash
# 67 — curl default flags include -k (--insecure)
_crlGet="-L --max-redirs 3 -k -s --retry 9 --retry-delay 9 -A iCab"

# 313–314 — http:// for every binary fetch
_urlDev="http://${_USE_MIR}/dev"
_urlHmr="http://${_USE_MIR}/versions/${_tRee}/boa/aegir"

# 419
_urlEnc="http://${_USE_MIR}/enc/2024"

# representative fetches (dozens like this in BOA.sh.txt:1150–1900)
curl ${_crlGet} "${_urlHmr}/tools/bin/lock.inc" -o ${_optBin}/lock.inc
curl ${_crlGet} "${_urlHmr}/tools/bin/boa" -o ${_optBin}/boa
curl ${_crlGet} "${_urlHmr}/tools/bin/octopus" -o ${_optBin}/octopus
curl ${_crlGet} "${_urlHmr}/tools/bin/mybackup" -o ${_optBin}/mybackup
curl ${_crlGet} "${_urlHmr}/tools/system/monitor/check/scan_nginx.sh" -o /var/xdrago/monitor/check/scan_nginx.sh
```

### Fix
Three independent improvements; pick at least the first.

1. **Switch `_urlDev`/`_urlHmr`/`_urlEnc` to `https://`** and remove `-k`
   from `_crlGet`. Requires confirming every BOA mirror in the
   fastest-mirror pool serves HTTPS with a valid certificate (Let's
   Encrypt or otherwise). Verify with
   `for h in files.aegir.cc ao.files.aegir.cc <others>; do
     curl -sIo /dev/null -w '%{http_code} %{ssl_verify_result}\n' \
       "https://$h/versions/dev/boa/aegir/tools/bin/lock.inc"; done`.

2. **Sign released artifacts** and verify the signatures during fetch.
   BOA generates and ships a public key; each fetch retrieves the
   signed-file pair `(<file>, <file>.sig)` and uses `gpg --verify`
   before chmod/chown/install. Stronger guarantee than HTTPS alone
   because it survives CDN-edge compromise.

3. **Verify SHA256 manifest.** Ship a single `MANIFEST.sha256` at the
   top of each release, signed (#2) or fetched separately, listing the
   expected hash of every BOA file. Fetch the manifest first, then
   verify each downloaded file against it before install. Cheaper than
   per-file signing, weaker than per-file signing.

Adam confirmed on 2026-05-24 that BOA mirrors will be switched to
HTTPS, and that per-file signing is not feasible at the hot-fix cadence
BOA operates at. Landing the URL flip + `-k` removal here. Signing /
manifest scheme deferred as a future hardening for if the threat model
ever expands to include mirror-server compromise (currently mitigated
by the mirrors being self-hosted under omega8cc).

The change covers:
- `_urlDev` / `_urlHmr` / `_urlEnc` definitions across all 20 affected
  files (top-level installer, satellite/master `.inc` libraries, the
  cron-driven `daily.sh` / `clear.sh` / `manage_ltd_users.sh` /
  `manage_solr_config.sh`, the backup scripts, and the
  `barracuda.sh.cnf` / `octopus.sh.cnf` settings templates).
- All literal `http://${_USE_MIR}` and `http://files.aegir.cc` URLs
  switched to `https://`.
- `_crlGet="-L --max-redirs 3 -k -s ..."` → `_crlGet="-L --max-redirs 3 -s ..."`
  across all 15 sites that defined it (drops `-k`).
- `_wgetGet="--max-redirect=3 --no-check-certificate ..."` →
  `_wgetGet="--max-redirect=3 ..."` across all 14 sites (drops the
  wget equivalent of `-k`; the audit caught this companion flag
  during the patch pass).

### Patch commit
PATCHED in follow-up commit.

---

## [MEDIUM] mysql_cleanup.sh interpolates table names into SQL heredocs without identifier quoting
**File:** aegir/tools/system/mysql_cleanup.sh  (lines 129, 140, 150, 160, 170, 180, 184)
**Category:** shell-injection (SQL identifier injection in root mysql context)
**Status:** PATCHED in follow-up commit

### Description
`mysql_cleanup.sh` runs as root from cron (`30 * * * *`) and iterates
over every database and over every table whose name matches a hardcoded
prefix (`cache*`, `watchdog`, `accesslog`, `batch`, `queue`,
`views_data_export_index_*`). For each match it executes:

```bash
mysql ${_DB}<<EOFMYSQL
TRUNCATE ${C};
EOFMYSQL
```

The table name `${C}` comes from `mysql -e "show tables" -s` output,
filtered by `grep ^cache | uniq | sort`. The interpolation is done with
**no SQL identifier quoting**.

A tenant who has CREATE privilege on their own database (which is the
normal Drupal-tenant grant) can create a table whose name starts with
`cache` and contains injection metacharacters. MySQL accepts almost any
identifier inside backticks, including semicolons and SQL keywords:

```sql
-- Created by the tenant via Drupal db_query or any mysql client:
CREATE TABLE `cache_evil`; DROP DATABASE `other_tenant_db`; -- ` (col INT);
```

When `mysql_cleanup.sh` later iterates and substitutes `${C}` (=
`` cache_evil`; DROP DATABASE `other_tenant_db`; -- ``) into the
heredoc, the resulting SQL becomes:

```sql
TRUNCATE cache_evil`; DROP DATABASE `other_tenant_db`; -- ;
```

mysql parses `TRUNCATE cache_evil` (illegal but the parser progresses
on `;`), then `DROP DATABASE other_tenant_db`, then a comment. The
DROP runs in **root mysql context** — the script connects with `-u root`
and the cron's effective credentials are root's `/root/.my.cnf` —
so the tenant has just cross-tenant-dropped another tenant's database.

This is **cross-tenant SQL injection via SQL-identifier name**. The
prerequisite (creating a table with a backtick-laden name in your own
DB) is achievable from any tenant Drupal site running a contrib module
or from a tenant with shell access via `mysql` (lshell-allowed).

### Evidence
```bash
# lines 119–133 — representative; the other 5 truncate loops use the same shape
_TABLES=$(mysql ${_DB} -u root -e "show tables" -s | grep ^cache | uniq | sort 2>&1)
for C in ${_TABLES}; do
  ...
  if [ -z "${_IF_SKIP_C}" ]; then
    mysql ${_DB}<<EOFMYSQL
TRUNCATE ${C};
EOFMYSQL
  fi
done
```

### Fix
Two-layer defence (apply both):

1. **Backtick-quote the identifier inside the SQL.**
   ```bash
   mysql ${_DB}<<EOFMYSQL
   TRUNCATE \`${C}\`;
   EOFMYSQL
   ```
   This makes ``cache_evil`; DROP`` show up inside backticks; a single
   backtick still escapes the quoting and lets the injection through.

2. **Reject any table name containing a backtick before using it.**
   ```bash
   if [[ "${C}" == *\`* ]]; then
     echo "WARN: skipping table with backtick in name: ${C}"
     continue
   fi
   ```
   Drupal core never creates tables with backticks in their names —
   this rejects the injection vector while keeping every legitimate
   table.

3. **Optional belt-and-braces:** restrict the for-loop to identifiers
   matching a positive allowlist `[A-Za-z0-9_]+` before passing to
   mysql.

The same pattern applies to all six loops in this file
(`_truncate_cache_tables`, `_truncate_watchdog_tables`,
`_truncate_accesslog_tables`, `_truncate_batch_tables`,
`_truncate_queue_tables`, `_truncate_views_data_export`).

Adam confirmed on 2026-05-24: only `[A-Za-z0-9_]+` should ever be
allowed for table/db identifiers in BOA; nothing else is used in
practice. Landed the positive-allowlist fix with `_is_safe_ident`
helper applied to every truncate/drop loop and to the outer
`for _DB in ...` database loop. Backtick-quoting added to every
SQL identifier as belt-and-braces — even though the allowlist makes
the quoting redundant today, it makes future audit work easier
because the SQL is now structurally correct.

Unsafe identifiers are logged (`WARN: skipping unsafe ... in ${_DB}:
${C}`) and skipped, never executed. The script's hourly cron continues
on the remaining tenants and tables.

### Patch commit
PATCHED in follow-up commit.

---

## [LOW] `find ... | xargs rm -f` is fragile to filenames with whitespace/newlines
**File:** aegir/tools/system/usage.sh  (lines 801–812); lib/functions/satellite.sh.inc  (lines 3238–3239)
**Category:** shell-injection
**Status:** NEEDS-REVIEW

### Description
Several scripts use the unsafe `find ... | xargs rm -f` pattern instead
of `find ... -delete` or `find ... -print0 | xargs -0 rm -f`.

```bash
# usage.sh:801–812 — runs in cwd /data/disk/<oct>/
find . -name "exclude.tag" -type f | xargs rm -f &> /dev/null
find . -name "*~" -type f | xargs rm -f &> /dev/null
# satellite.sh.inc:3238 — runs in cwd /data/disk/all/aegir/distro (root-owned)
find . -name .DS_Store -type f | xargs rm -f &> /dev/null
```

xargs splits its input on whitespace by default. A filename containing
a newline is split into two args; if either of the resulting args
matches an existing file in cwd, that file is also deleted.

In `usage.sh`, the cwd is the per-octopus root `/data/disk/<oct>/`,
which is tenant-writable in many subdirectories. A tenant can plant a
file with a crafted name to cause cross-file deletion within their own
tree. In `satellite.sh.inc`, the cwd is the BOA-managed root
`/data/disk/all/aegir/distro` — not tenant-writable, so the impact is
theoretical.

Severity LOW because:
- The blast radius is confined to the tenant's own directory tree.
- Leading `-` in filenames doesn't trick `rm` here: find prints paths
  prefixed with `./`, so `-r` becomes `./-r` (a literal pathname, not a
  rm option).
- This is a long-standing bash robustness gap, not a recent regression.

### Evidence
See file references above.

### Fix
Convert to one of:
- `find ... -type f -delete` (shortest, requires GNU find 4.2+).
- `find ... -type f -print0 | xargs -0 rm -f`.
- `find ... -type f -exec rm -f {} +`.

The third form (`-exec rm -f {} +`) is the most portable and matches
the existing style of `find ... -exec chmod ... {} \;` already used
elsewhere in BOA. Recommend this form.

### Patch commit
PENDING — small but touches many lines across two files. Recommend
combining with the boa-modernisation `find` normalisation pass.

---

## [INFO] mysql_cleanup.sh `${_DB}` interpolation also lacks identifier quoting
**File:** aegir/tools/system/mysql_cleanup.sh  (line 129 and parallel)
**Category:** shell-injection
**Status:** INFO

### Description
The `mysql ${_DB}<<EOFMYSQL ...` invocations pass `${_DB}` as the
positional database-name argument to mysql. `_DB` is iterated from
`mysql -e "show databases" -s` output, filtered against `Database`,
`information_schema`, `performance_schema`. mysql database names are
typically constrained to `[A-Za-z0-9_$]`, but again backticks accept
almost anything.

A maliciously named database (`evil\`; show grants; --`) would arrive
at mysql as the cmdline arg `-u root evil`; show grants; --`. Shell
already handled the parsing (the `\`` is inside backticks within the
shell-script source); the mysql client sees the literal db name.
The mysql client then issues `USE evil` followed by the literal
SQL statements in the heredoc. Cross-tenant impact is minimal because
mysql cmdline doesn't re-parse the db name as SQL.

The more dangerous case is the TABLE name interpolation inside the
heredoc, covered by finding #2 above.

### Fix
None standalone. The fix for finding #2 (reject backticks in
identifiers before use) naturally covers this too if applied to `${_DB}`
in the outer loop at line 189.

### Patch commit
N/A (covered by #2).

---

## [INFO] Drush alias parsing pipelines reuse the same cut+awk+sed pattern in many places
**File:** aegir/tools/system/daily.sh:2406, 2412, 3005; lib/functions/satellite.sh.inc; aegir/tools/system/monitor/check/segfault_alert.pl:142+
**Category:** shell-injection
**Status:** INFO — verified safe in shape

### Description
A recurring pipeline extracts `site_path` and `root` from Drush alias
PHP files:

```bash
cat ${_usEr}/.drush/${_Dan}.alias.drushrc.php \
  | grep "site_path'" \
  | cut -d: -f2 \
  | awk '{ print $3}' \
  | sed "s/[\,']//g"
```

The output (`_Dir`, `_Plr`) is then used in many chmod/chown commands.
Category-3 finding addresses the chmod/chown symlink-following surface;
category-4 finding adds path-prefix validation. The pipeline itself
is not an injection sink — the output is captured into a variable and
used as a path argument, not interpolated into a constructed shell
command.

awk `$3` was discussed in the segfault_alert.pl finding (the Perl
backtick context interpolates `$3` before the shell). In daily.sh this
is bash-context: `$3` inside single quotes is literal text passed to
awk as the script body, where awk interprets `$3` as field 3. Correct.

### Fix
N/A.

### Patch commit
N/A.

---

## [INFO] Many `for X in $(find ...)` and `for X in \`dir -d ...\`` loops are fragile to filenames with spaces
**File:** aegir/tools/system/daily.sh:2807,2826,2842; lib/functions/satellite.sh.inc:3656,3675,3691; lib/functions/nginx.sh.inc:986; aegir/tools/system/manage_solr_config.sh:814,819,965; aegir/tools/system/runner.sh:99
**Category:** shell-injection
**Status:** INFO

### Description
Many loops iterate over `find` or `dir -d` output via `$(...)` or
backtick command substitution. The for-loop word-splitting breaks any
filename that contains whitespace or globs.

For most of these the cwd is a BOA-managed directory tree where
tenants cannot create directories. The few that iterate inside
tenant-writable trees (e.g. `/data/disk/<oct>/distro/`) split tenant-
named platform directories on whitespace. Loop bodies check
`[ -e "${i}" ]` first, so misnamed iterations no-op rather than
operate on the wrong file. No demonstrated security impact.

### Fix
Convert to `while IFS= read -r ... ; do ... done < <(find ... -print)`
or to `find ... -print0 | while IFS= read -r -d '' ...` for explicit
NUL-delimited iteration. Defence-in-depth, not a current vulnerability.

### Patch commit
N/A — fold into boa-modernisation `find` normalisation pass.

---

## [INFO] mybackup queue-file injection — fixed in category 4
**File:** aegir/tools/bin/mybackup
**Category:** shell-injection
**Status:** RESOLVED via category 4 commit `ab01133e5`

### Description
The mybackup `<user>.ftp` → system-user lshell escape via shell-
interpolation of the queue-file content into `su -c "mybackup
${_command}"` was identified in category 4 (variable-handling) and
patched there. Cross-referenced here because it falls into the
shell-injection class too.

### Fix
N/A — landed in `ab01133e5`.

### Patch commit
ab01133e5.
