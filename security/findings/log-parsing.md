# Findings: Log Parsing and Code Execution via Log Content

Covers scripts that consume Nginx, PHP-FPM, MySQL, lshell, or system logs and pass content to interpreters.

Findings are appended below as they are discovered. Each entry follows the schema defined
in CLAUDE.md. Most-recent findings appear at the bottom.

---

## Audit scope coverage

Active log consumers reviewed in this pass:

| Script | Reads | Action |
|---|---|---|
| `aegir/tools/system/monitor/check/scan_nginx.sh` | `/var/log/nginx/access.log` | CSF block + `monitor/log/web.log` append |
| `aegir/tools/system/monitor/check/hackcheck.sh` | `/var/log/auth.log` | CSF block + `monitor/log/ssh.log` append |
| `aegir/tools/system/monitor/check/hackftp.sh` | `/var/log/messages` | CSF block + `monitor/log/ftp.log` append |
| `aegir/tools/system/monitor/check/escapecheck.sh` | `/var/log/lsh/*.log` | email alert via s-nail |
| `aegir/tools/system/monitor/check/segfault_alert.pl` | `/var/log/syslog`, `/var/log/nginx/access.log`, Drush aliases | email alert + log append |
| `aegir/tools/system/monitor/check/sqlcheck.pl` | `/var/log/syslog` (mysql lines) | triggers `checksql.pl` |
| `aegir/tools/system/checksql.pl` | `mysqlcheck` output | generates and runs repair shell script + email |
| `aegir/tools/system/proc_num_ctrl.pl` | `ps auxf` output (treated as a log) | service restart, `kill -9` |
| `lib/functions/*.inc` (various) | install/upgrade logs, `cli.txt`/`fpm.txt` | boolean flag for installer decisions |

Dead code (replaced by `.sh` equivalents, **not** fetched by `BOA.sh.txt` on install,
**not** invoked from cron):

- `aegir/tools/system/monitor/check/hackcheck.pl`
- `aegir/tools/system/monitor/check/hackftp.pl`
- `aegir/tools/system/monitor/check/escapecheck.pl`

Confirmed inactive by:
1. `aegir/tools/system/cron/crontabs/root` invokes only `second.sh` → which only
   spawns the `.sh` variants of these three monitors.
2. `BOA.sh.txt` downloads only the `.sh` files for these three from the BOA mirror.
3. `monitor/check/mysql.sh` and `monitor/check/php.sh` are the only callers of the
   remaining live Perl monitors (`sqlcheck.pl` and `segfault_alert.pl`).

The .sh replacement monitors are well-hardened: IFS pinned to `$'\n\t'`, log
content only ever compared against fixed regex on the LHS of `[[ =~ ]]`, IPs
validated by regex + range check before any external invocation, CSF arguments
quoted, no log content interpolated into `eval`, `bash -c`, or backticks.

---

## [MEDIUM] segfault_alert.pl interpolates multiple log-derived variables into shell via backticks
**File:** aegir/tools/system/monitor/check/segfault_alert.pl  (lines 101–105, 131, 133, 142, 144, 147, 150, 159, 207)
**Category:** log-parsing
**Status:** NEEDS-REVIEW

### Description
The Perl segfault monitor runs as root from the cron-driven `monitor/check/php.sh`
chain. It reads `/var/log/syslog` and `/var/log/nginx/access.log`, then constructs
shell commands via Perl backticks with interpolated variables. The fragile pattern
is documented inline by a `TODO - rewrite this legacy script in bash` comment.

Current state is safe **only because the data sources are root-owned or
internally validated**. The reasoning is non-obvious and fragile to future change:

- `$CRASH`/`$CRASHED` is sanitised at line 68 (allowed chars `[a-zA-Z0-9:\s\t/\-@_()*\[\].,]`)
  and then further restricted to digits-plus-colon at line 72 (`$TIMEX =~ s/[^0-9\:]//g`).
  Interpolated into `\`grep "$CRASHED.* 502 " /var/log/nginx/access.log\`` at line 131
  and `\`grep "$CRASHED.*php\-.*: segfault" /var/log/syslog\`` at line 133. Safe today.
- `$d` (the matched domain) is sanitised at line 137 (`[a-z0-9.-]+` only) before
  being interpolated into the `cat /data/disk/*/.drush/$d.alias.drushrc.php | ...`
  pipelines at lines 142, 144, 147, 150. Safe today.
- `$ngxl`, `$sysl`, `$pthl`, `$disl` are written to a log file via `\`echo "...$var..." >> $this_path\``
  at lines 101–105. Each is sanitised: `$ngxl`/`$sysl` go through the
  `s/[^...]//g` filter at lines 132/134 and a further `s/([";])/\\$1/g`
  shell-quote-escape at lines 170/172. Safe today.
- `$email` is read from root-owned `/root/.barracuda.cnf`. Safe.
- `$cmail` is read from `/data/disk/$rx/log/email.txt`, line 197. **This is the
  only variable in the file whose source location is per-tenant.** The directory
  `/data/disk/<oct>/log/` is created via `mkdir -p` at root invocation
  (`lib/functions/satellite.sh.inc:6029`) and is NEVER explicitly chowned to the
  Octopus admin user; the parent `/data/disk/<oct>/` is mode 0711 root:root
  (`lib/functions/satellite.sh.inc:2423`). The Octopus admin therefore cannot
  write or replace `email.txt`. Safe today.
- `$rx` is extracted from the Drush alias file (root-owned). The alias path
  itself is constructed via brace-glob `cat /data/disk/*/.drush/$d.alias.drushrc.php`
  where `$d` is the validated domain — see above.

The pattern is **defense-by-coincidence**. Each interpolation depends on a
specific upstream chowmask, sanitiser, or mkdir-without-chown to remain safe.
A future change to any of those — for example chowning `/data/disk/<oct>/log/`
to the Octopus admin to allow the operator to write `email.txt` from a
self-service control panel — converts this into an immediate root-shell
escalation from the Octopus tenant.

Additionally, lines 142, 144, 147, 150 contain a latent bug not directly
security-relevant: `awk '{ print $3}'` is inside Perl backticks (which behave
like double-quoted strings); Perl interpolates `$3` as a Perl regex-capture
variable (undefined → empty) before the string reaches the shell. The awk
script becomes `'{ print }'` (no field). The adjacent `cut -d: -f2` already
extracts the desired column so the awk step is a no-op; remove or repair it
in the rewrite.

### Evidence
```perl
# line 131
$ngxl=`grep "$CRASHED.* 502 " /var/log/nginx/access.log`;
# line 133
$sysl=`grep "$CRASHED.*php\-.*: segfault" /var/log/syslog`;
# line 142
$pthl=`cat /data/disk/*/.drush/$d.alias.drushrc.php | grep 'site_path' | cut -d: -f2 | awk '{ print $3}' | sed "s/[\,']//g"`;
# line 207
`cat $this_path | s-nail -b $email -s "PHP Segfault Alert for [$dx] at [$s] on $t" $cmail`;
```

### Fix
The right fix is the rewrite already TODO-flagged at the top of the file:
port `segfault_alert.pl` to bash following the same hardened style used in
`hackcheck.sh`/`hackftp.sh`/`escapecheck.sh` (regex-anchored extraction, no
shell interpolation of log content, `printf` with explicit format strings
for any log content written to files, IPs/domains validated by both regex
and structural check before any external invocation).

Interim defensive change that does not require the full rewrite:
1. In `_send_alert`, validate `$email` and `$cmail` against a strict email regex
   (`^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$`) before any backtick
   interpolation; bail with a clear log message if the value fails.
2. Replace the line 207 backtick with `system()` in list form:
   `system('s-nail', '-b', $email, '-s', "...", $cmail) == 0 or warn ...;`
   followed by piping `$this_path` content via Perl, not via `cat ... |`.
3. Re-do `find_domain` extraction via Perl regex against an in-memory copy of
   the log line rather than `grep $CRASHED log_file`.

NEEDS-REVIEW: this is a workstream-sized rewrite, not a single audit patch.
Recommend scheduling against `boa-modernisation` and applying the interim
defensive change ahead of the rewrite if any further changes touch this file.

### Patch commit
PENDING — interim defence and full rewrite both deferred. See DECISIONS.md.

---

## [LOW] scan_nginx.sh echoes attacker-controlled UA prefix to terminal/log
**File:** aegir/tools/system/monitor/check/scan_nginx.sh  (line 694)
**Category:** log-parsing
**Status:** PATCHED in this commit (defensive filter added)

### Description
`scan_nginx.sh` extracts the request User-Agent from Nginx access-log lines
(line 1064 regex match). When a DDoS UA fingerprint is detected, the UA is
truncated to 120 chars and echoed to stdout (line 694) and to the verbose log
via `_verbose_log` (line 692). `_verbose_log` uses
`printf "%s %s REASON: %s\n"` with the UA as a data argument — no format-string
injection. However, the bare `echo` at line 694 emits any terminal escape
sequences contained in the UA verbatim. A sysadmin viewing the cron output
via `journalctl -t cron` or `tail -f` would see manipulated terminal output;
on most modern terminals this is cosmetic (no command execution), but on a
serial console or `screen`/`tmux` capture-then-replay path it can confuse the
operator about which IPs were blocked.

No RCE path. Echoing happens in a root-context cron — the UA never reaches
`eval`, `bash -c`, command substitution, or any shell interpolation.

### Evidence
```bash
# line 694
echo "=== UA fingerprint: ${_UA:0:120} ==="
```

### Fix
Strip non-printable characters from the UA before echo and before the
`_verbose_log` call, using bash parameter expansion (no fork to `tr`/`sed`).

### Patch commit
PATCHED — see commit message below.

---

## [LOW] scan_nginx.sh accepts off-spec IPv4 octets into UA/path-flood tracking
**File:** aegir/tools/system/monitor/check/scan_nginx.sh  (lines 992–995, 1064–1072, 1084–1100)
**Category:** log-parsing
**Status:** PATCHED in this commit

### Description
The main per-line loop validates IPs against the loose regex
`^([0-9]{1,3}\.){3}[0-9]{1,3}$` at line 992 (octet ≤ 999) and only applies the
strict octet-range check inside `_process_ip` via `_validate_ip` at line 465.
`_track_ua_ip` and `_track_path_flood` are called from the same loop at lines
1070 and 1093 with the unfiltered loose-regex IPs. Off-spec strings such as
`999.999.999.999` propagate into the `_UA_IP_LIST` / `_PATH_IP_LIST` arrays
and then to `_block_ip` → `csf -td "${_IP}" 900 -p 80`. CSF re-validates and
the bad input is rejected; no exec path.

This is hygiene rather than a vulnerability — there is no log-derived data
that reaches an interpreter. The fix is to apply the same `_validate_ip`
gate that `_process_ip` uses.

### Evidence
```bash
# line 992
if [[ "${_ip_candidate}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  _IP_LIST+=("${_ip_candidate}")
fi
# ...
# line 1070 (UA tracking)
_track_ua_ip "${_REAL_IP}" "${_DDOS_UA}"
# line 1093 (path-flood tracking)
_track_path_flood "${_REAL_IP}" "${_WPFX}" "${_LINE_STATUS}" "${_UP_TIME}"
```

### Fix
Tighten the per-candidate regex check at line 992 to a single call to
`_validate_ip` (which performs both the regex match and the octet-range check).
This is a one-line change with no behavioural impact on valid IPs.

### Patch commit
PATCHED — see commit message below.

---

## [INFO] checksql.pl reads MySQL root password into Perl variable but never uses it
**File:** aegir/tools/system/checksql.pl  (line 26)
**Category:** log-parsing (cross-cuts credential-exposure)
**Status:** INFO — flagged for category 6 (credential-exposure) follow-up

### Description
```perl
$mysqlrootpass=`cat /root/.my.pass.txt`;
chomp($mysqlrootpass);
```

The variable is never referenced afterwards. The script obtains MySQL access
via `/root/.my.cnf` (mysqlcheck reads it implicitly). Dead code that
unnecessarily loads the plaintext root password into the Perl process address
space (where it sits in unaudited Perl memory and may end up in core dumps).

Not strictly a log-parsing issue. Recording here to ensure it gets picked up
when category 6 (credential-exposure) starts.

### Fix
Remove the read entirely; the variable is dead.

### Patch commit
N/A in this commit; deferred to credential-exposure category.

---

## [INFO] Three Perl monitors are dead code still present in the source tree
**File:** aegir/tools/system/monitor/check/hackcheck.pl, hackftp.pl, escapecheck.pl
**Category:** log-parsing
**Status:** INFO

### Description
These three Perl monitors have `.sh` replacements that run from cron. The
`.pl` files:
- are NOT downloaded by `BOA.sh.txt` on install (`grep -nE 'hackcheck\.pl|hackftp\.pl|escapecheck\.pl' BOA.sh.txt` returns zero results)
- are NOT invoked by any active cron-reachable code path
- contain the older unhardened backtick patterns (e.g. `hackcheck.pl:95` runs
  `\`/usr/sbin/csf -td $VISITOR 3600 -p 22\`` with $VISITOR derived from log content;
  `escapecheck.pl:69` runs `\`echo "$line" >> $logfile\`` with $line being a
  sanitised but still-attacker-influenced log line)

They will never execute on a current BOA install — but they remain in the
repository where someone might copy-paste from them, and a future build
script change that re-enables them would silently regress the security
posture.

### Fix
Delete the three files from the source tree. The CHANGELOG already notes the
`.sh` replacement work. Deletion does not change runtime behavior; it removes
a future-tense regression risk.

### Patch commit
NOT PATCHED in this commit — pure-removal commits are reviewed separately by
Adam (he handles public-branch surfacing). Recommendation is to delete them in
a dedicated `cleanup: remove dead Perl monitors` commit once Adam confirms no
hidden caller exists.

---

## [INFO] Many lib/functions/*.inc consumers grep system logs only to set boolean flags
**File:** lib/functions/master.sh.inc:1423; lib/functions/satellite.sh.inc:5168; lib/functions/system.sh.inc:602,1727–1811,6716; lib/functions/php.sh.inc:2603
**Category:** log-parsing
**Status:** INFO — verified safe

### Description
A number of `.inc` helpers read system logs to drive installer/upgrade
decisions:

- `master.sh.inc:1423` / `satellite.sh.inc:5168` — extract the Aegir
  one-time-login URL from `/var/log/boa/aegir_install.log` (root-owned).
- `system.sh.inc:602` — `grep "fatal: open lock file" /var/log/mail.log` to
  flag a Postfix restart need.
- `system.sh.inc:1727..1811` — `grep "5\.[2345]" /data/disk/*/log/{cli,fpm}.txt`
  to detect tenants still on legacy PHP versions before an upgrade.
- `system.sh.inc:6716` — `cat /var/lib/proxysql/pxc_test_proxysql_galera_check.log`.
- `php.sh.inc:2603` — `grep OnigEncoding /var/log/php/php$1-fpm-error.log`.

In every case the grep output is captured into a variable that is then only
used as the LHS of `[[ =~ ]]` regex matches or `[ -z ... ]` emptiness tests.
None of the captured content reaches `eval`, `bash -c`, command substitution,
or external invocation as an argument. **Verified safe.**

### Fix
N/A.

### Patch commit
N/A.
