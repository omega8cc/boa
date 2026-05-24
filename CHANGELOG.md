# Changelog — [PROJECT NAME]

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html) where applicable,
otherwise date-stamped entries for non-versioned work.

---

## [Unreleased]

### Added
- `aegir/conf/tpl/maintenance.html` — generic 503 maintenance template,
  deployed to `/var/www/nginx-default/maintenance.html` by `_nginx_mime_check_fix`.
- HTTP-off migration short-circuit in both `aegir/conf/global/global.inc`
  (legacy single-file) and `aegir/conf/global/global-mode.inc` (modern
  shared): presence of `/data/disk/<oct>/static/control/http-off.pid` makes
  every site on the account return 503 with `Retry-After`, `X-Accel-Expires`
  (Nginx microcache), and `Cache-Control` headers. TTL is read from the pid
  file contents (default 300s, clamped 30..86400).

### Changed
- `xboa` export step now creates the per-account `http-off.pid` (default
  3600s TTL) and purges `/var/lib/nginx/speed` so already-cached 200
  responses on hot URLs (homepages especially) cannot mask the 503.
- `xboa` proxy step removes `http-off.pid` after Nginx reload and purges
  the speed cache again before writing `proxied.pid`, so cached 503s do
  not linger after the proxy vhost takes over.

### Fixed
- Migration data-consistency on Drupal 8+ sites and on busy commerce/API
  sites where `readonlymode` is unavailable via system drush 8 or bypassed
  by application code paths.
- security: category-8 (misc) sweep complete. No new patches landed —
  the prior seven category passes caught every actionable item. Two
  LOW items documented for follow-up: Node.js `curl|bash` install
  path in `xtra.sh.inc` (runs only on single-tenant hosts per BOA's
  no-Node-on-multi-tenant policy) and the `/tmp/virtwhat.$$.strace`
  predictable filename (install-time only, no untrusted users
  present). See `security/findings/misc.md` for cross-references to
  the categories that handled MD5/SHA1, FTP-as-FTPS-only, SUID
  intent, umask defaults, and password-generation RNG.
- security: PHP ini hardening across all 24 templates (12 versions ×
  `{.ini, -cli.ini}`): `expose_php Off` (drops `X-Powered-By` version
  leak), `session.use_strict_mode 1` (blocks session-fixation), and
  `session.cookie_samesite Lax` (CSRF mitigation; only for PHP 7.3+
  where the directive exists).
- security: Nginx `http{}` block grows `server_tokens off` — drops
  the `Server: nginx/X.Y.Z` version leak in response headers and
  default error pages.
- security: MySQL/Percona `[mysqld]` gets explicit `local_infile = OFF`
  in the BOA template. No-op on Percona 8.x (already the default);
  closes the client-side LOAD DATA LOCAL INFILE file-read class on
  Percona 5.7 (where the default is ON).
- security: sshd `ClientAliveCountMax` lowered from 10000 (~34 days
  idle-tolerance) to 3 (15 min idle-disconnect window).
- security: sysctl template grows three recent kernel-hardening
  knobs: `kernel.unprivileged_bpf_disabled = 1` (blocks eBPF-CVE
  class for non-root users), `net.core.bpf_jit_harden = 2`
  (JIT-spray hardening), `vm.unprivileged_userfaultfd = 0`
  (closes userfaultfd-as-race-amplifier class).
- security: BOA PI mode — full /proc/PID/cmdline credential-disclosure
  closure. Five linked changes:
    1. `helper.sh.inc` adds `_check_proc_hidepid` — installs a
       `hidepid=2,gid=adm` entry in /etc/fstab, remounts /proc with
       those options, and adds `aegir` to the `adm` group so
       hostmaster operations retain process visibility. Per-Octopus
       system users and lshell-restricted `.ftp` accounts get only
       own-process visibility, closing the entire class of
       cross-tenant /proc/cmdline disclosures with one mount option.
       Wired into `BARRACUDA.sh.txt` right after
       `_check_prepare_dirs_permissions`.
    2. `helper.sh.inc` adds `_write_proxysql_adm_cnf` /
       `_write_cluster_root_cnf` helpers that emit 0600-root cnfs
       suitable for `mysql --defaults-extra-file=`. Replaces 13 sites
       of `mysql -uadmin -p${_PROXYSQL_PASSWORD} -h127.0.0.1 -P6032
       --protocol=tcp` in master/satellite/system .inc with
       `mysql --defaults-extra-file=/root/.my.proxysql_adm.cnf`.
    3. `manage_ltd_users.sh` and `satellite.sh.inc` switch from
       `mkpasswd "${pwd}"` / `usermod -p $ph` (both visible in
       /proc) to `printf '%s' "${pwd}" | mkpasswd -m sha-512 -s -S
       "${salt}"` and `printf '%s:%s\n' user hash | chpasswd -e` —
       password and hash never reach cmdline.
    4. `mysql_backup.sh` switches `mydumper --password=${_SQL_PSWD}`
       to `mydumper --defaults-file=/root/.my.cnf`. The dead
       `_SQL_PSWD=$(cat /root/.my.pass.txt)` read removed.
       `mysql_cluster_backup.sh` regenerates
       `/root/.my.cluster_root.cnf` (0600 root:root) each run from
       the cluster root password file and resolved host/port, and
       replaces the `_C_SQL="mysql --user=root --password=..."`
       template with `mysql --defaults-extra-file=...`. mydumper /
       mysqldump / mysqlcheck calls switched the same way.
    5. `duplicity_backup.sh` switches 4 of 6 cloud-storage providers
       (cloudflare/R2, do_spaces, linode, wasabi) from
       `s3://KEY:SECRET@endpoint/bucket` URL embedding to
       `boto3+s3://endpoint/bucket` + `AWS_ACCESS_KEY_ID` /
       `AWS_SECRET_ACCESS_KEY` env exports. b2 URL drops the
       application_key portion (read from env). ibmcos backend has
       no env-var alternative — tracked as residual LOW.
- security: `mysql_backup.sh` and `mysql_cluster_backup.sh` apply the
  same `_is_safe_ident` allowlist on database and table identifiers
  that `mysql_cleanup.sh` got in the previous audit pass. Closes the
  cross-tenant `DROP DATABASE` path via tenant-named tables containing
  backticks. All SQL identifiers in TRUNCATE/DROP/OPTIMIZE/ALTER
  heredocs also backtick-quoted as belt-and-braces.
- security: `/var/log/boa/aegir_install.log` set to mode 0600 in
  `master.sh.inc:1219` immediately after the existing `chown
  aegir:aegir`. The install log captures the Aegir one-time-login URL
  briefly during install; world-readable mode 0644 (the previous
  default) let any local user race to redeem the OTLU.
- security: removed 4 dead `_SQL_PSWD=$(cat /root/.my.pass.txt)` reads
  in `BOA.sh.txt`, `aegir/tools/system/move_sql.sh`,
  `aegir/tools/system/mysql_repair.sh`, and
  `aegir/tools/system/checksql.pl`. Each loaded the cleartext MySQL
  root password into the script's process memory without ever
  referencing the variable afterwards (mysql/mysqlcheck calls in
  those scripts use /root/.my.cnf credentials implicitly).
- security: `aegir/tools/system/monitor/check/mysql.sh:172` no longer
  reads the MySQL root password into a shell variable to test its
  non-emptiness — uses `[ -s /root/.my.pass.txt ]` directly.
- security: BOA installer/upgrader and runtime fetch chain switched
  from plain HTTP to HTTPS, and from cert-insecure curl/wget defaults
  to cert-validating defaults. `_urlDev`/`_urlHmr`/`_urlEnc` now use
  `https://${_USE_MIR}/...`. `_crlGet` drops `-k` (curl's
  `--insecure`); `_wgetGet` drops `--no-check-certificate` (the wget
  equivalent). 20 files updated covering the top-level installer, the
  satellite/master library, the cron-driven monitors, the backup
  scripts, and the runtime settings templates. Closes the
  network-MITM-to-root supply-chain exposure during install/upgrade.
- security: `mysql_cleanup.sh` rejects database and table identifiers
  that do not match `[A-Za-z0-9_]+` before passing them to root mysql.
  All seven SQL loops (six per-table-pattern + the outer per-database
  loop) gated by a new `_is_safe_ident` helper. SQL identifiers in the
  heredocs also backtick-quoted as belt-and-braces. Closes the
  cross-tenant `DROP DATABASE` path via a tenant-created table with
  backticks in its name.
- security: `mybackup` queued-command file format is now one argument
  per line (`printf '%s\n' "$@"`) instead of a space-joined string. The
  root-cron consumer reads it via `mapfile -t`, re-applies
  `_validate_restore_command` against the parsed args, and executes
  via `su -s /bin/bash - <user> -c 'exec mybackup "$@"' -- "${args[@]}"`
  so each arg arrives positionally with no shell-metacharacter
  interpretation. The validator now forbids whitespace and the shell
  metacharacter set in `_restore_path`. A defence-in-depth re-validation
  also runs on the system-user execution path before `_restore`'s
  duplicity-eval. Closes the lshell-to-system-user escape via direct
  queue-file tampering by `.ftp` operators (the queue file lives under
  the `.ftp`-owned `static/control/.run/` tree).
- security: `lock.inc` opens and closes its lock file descriptor via
  bash's `exec {var}>...` auto-assignment form instead of `eval "exec
  ${var}>..."`. Same behaviour for the current caller set, removes the
  eval seam if a future caller ever passes a non-static fd or path.
- security: `daily.sh` no longer follows attacker-controlled symlinks
  during the per-site chown sweep. `chown -L -R` (which explicitly
  dereferenced links during recursion) replaced with `chown -h -R`
  at lines 1725/1738/1745, and a `_validate_safe_dir` helper now
  realpath-canonicalises the alias-derived `_Dir`/`_Plr` paths and
  skips the loop iteration unless they resolve under `/data/disk/`,
  `/var/aegir/`, or `/home/`.
- security: `/var/tmp/fpm` (PHP-FPM opcache lockfile path) created
  with mode 1777 (sticky) instead of 0777. Prevents cross-tenant
  deletion of opcache lockfiles between PHP-FPM pools running as
  different per-tenant uids.
- security: `/var/log/php*` set to mode 0755 root:adm instead of 0777.
  Cross-tenant pool-name enumeration and arbitrary-file creation in
  the log directory are now blocked; PHP-FPM workers still append to
  pool logs via the master's inherited fd.
- security: `/opt/tmp` (BOA scratch root) created with mode 1777
  (sticky) instead of `chmod -R 777`. Matches the sticky-scratch model
  already used for `/var/tmp/fpm` and `/opt/user/{gems,npm}`. The
  explicit `find /opt/tmp/boa -exec chmod` calls still set the boa
  subtree to 0755/0644; other subtrees keep their existing modes
  rather than being blanket-rewritten on every install/upgrade.
- security: `/data/conf/arch/log` set to mode 0755 instead of 0777
  in both `system.sh.inc` and `satellite.sh.inc`. The directory is
  vestigial (no writer in the current codebase); tightening prevents
  any future feature from inheriting a wide-open creator surface.
- security: `scan_nginx.sh` strips non-printable characters from the
  DDoS-UA fingerprint before echo and verbose-log emission. Prevents an
  attacker-controlled User-Agent from injecting terminal escape sequences
  into cron stdout / `tail -f` views; no behavioural change for legitimate
  UAs.
- security: `scan_nginx.sh` per-line IP candidate filter now calls
  `_validate_ip` (which adds the per-octet 0..255 range check) instead of
  the loose regex `^([0-9]{1,3}\.){3}[0-9]{1,3}$`. Off-spec strings such
  as `999.999.999.999` no longer enter the UA-tracking and path-flood
  associative arrays. csf already rejected them downstream — this just
  filters earlier.
- security: NOPASSWD-sudo helpers harden against caller-planted symlinks.
  `aegir/tools/bin/fix-drupal-{platform,site}-{ownership,permissions}.sh`
  and `aegir/tools/bin/lock-local-drush-permissions.sh` now validate
  `--root`/`--site-path` resolves under `/var/aegir/`, `/data/disk/`, or
  `/home/`; `chown -L -R` replaced with `chown -h -R`; every direct
  `chmod` routed through a wrapper that skips symlinks. Closes the
  tar-archive-with-symlink → aegir → root escalation path.

### Removed
- `xboa`: drush8 `en readonlymode -y` call in the per-site export step and
  the long-commented-out `dis readonlymode` block in the per-site import
  step. The PHP-level http-off mechanism supersedes both.

---

<!-- Add versioned or dated releases below, newest first -->

## [0.1.0] — YYYY-MM-DD

### Added
- Initial project structure
- CLAUDE.md, DECISIONS.md, CHANGELOG.md
