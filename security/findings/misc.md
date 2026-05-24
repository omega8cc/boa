# Findings: Miscellaneous Bad Practices

Catch-all for the audit. Covers deprecated/unsafe network tools, weak hash
algorithms, predictable temp paths, script self-update via curl|bash,
residual `chmod 777` / SUID/SGID grants, and any other miscellaneous
items that don't fit the prior seven categories.

Findings are appended below as they are discovered. Each entry follows the schema
defined in CLAUDE.md. Most-recent findings appear at the bottom.

---

## Audit scope coverage

- `telnet`/`rsh`/`rcp`/`rlogin`/`tftpd` package usage.
- pure-ftpd configuration (FTP server is a deprecated protocol class
  when not over TLS).
- MD5 / SHA1 usage across all BOA scripts and Perl helpers.
- Predictable temp filenames; mktemp coverage gaps (cat-3 carry-over).
- `curl|bash` and `wget|bash` patterns; script self-update flows.
- Residual `chmod 777` / `chmod a+w` / SUID/SGID grants after the cat-3
  patches landed.
- RNG sources for password generation.
- Cipher allowlists / blocklists for TLS-bearing services.
- umask defaults.

---

## [LOW] Node.js install via `curl https://deb.nodesource.com/setup_22.x | sudo bash -`
**File:** lib/functions/xtra.sh.inc  (lines 431, 433)
**Category:** misc (script-self-update / supply-chain)
**Status:** NEEDS-REVIEW

### Description
BOA's Node.js install path pipes a remote script from nodesource.com
into `sudo bash`:

```bash
if [ "${_OS_CODE}" = "stretch" ] || [ "${_OS_CODE}" = "jessie" ]; then
  _mrun "curl -sL https://deb.nodesource.com/setup_16.x | sudo -E bash -"
else
  _mrun "curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -"
fi
```

The fetch is HTTPS (we already fixed cat 5 to drop `-k`), so a network
MITM cannot substitute the script — but a compromise of nodesource's
CDN or the underlying server would execute attacker code as root
on every BOA host that runs this install path.

Mitigating factor (per Adam's category-1 confirmation): **Node.js
tools are never installed on multi-user systems** because they
trivially break lshell confinement. The `xtra.sh.inc` Node block
runs only on single-tenant hosts where the operator already owns the
box. The threat shape is "the operator chose to run nodesource's
script" — they could have done that themselves.

On multi-tenant BOA hosts (the actual security-sensitive targets),
this code path is never exercised.

### Evidence
```bash
# xtra.sh.inc:431-433
_mrun "curl -sL https://deb.nodesource.com/setup_16.x | sudo -E bash -"
_mrun "curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -"
```

### Fix
Manual apt-repo + GPG-key install. nodesource publishes their signing
key at `https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key`.
Steps:

```bash
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg
chmod 0644 /usr/share/keyrings/nodesource.gpg
echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] \
  https://deb.nodesource.com/node_22.x nodistro main" \
  > /etc/apt/sources.list.d/nodesource.list
apt-get update
apt-get install -y nodejs
```

Same end-state but no `curl|bash`. Apt then verifies every package
via the pinned GPG key, so future package installs are protected
against CDN compromise.

NEEDS-REVIEW: low priority because the Node install path runs only on
single-tenant boxes. Bundle with the next xtra.sh.inc refactor; not
worth a focused commit in this audit pass.

### Patch commit
PENDING — deferred to a focused xtra.sh.inc refactor.

---

## [INFO] `telnet` client package is installed by BOA
**File:** lib/functions/system.sh.inc  (line 6375)
**Category:** misc (deprecated tool)
**Status:** INFO — verified acceptable

### Description
```bash
for _PKG in sysstat telnet cron gnupg2 gnupg ...; do
  if ! _pkg_installed "${_PKG}"; then
    _mrun "${_INSTAPP} ${_PKG}"
  fi
done
```

The Debian `telnet` package ships only the `telnet` CLIENT (not
`telnetd`); the server-side daemon would be in `telnetd` / `inetd`,
neither of which BOA installs. Operators sometimes use `telnet` as
a generic TCP-port-tester (`telnet host 25` to read an SMTP banner).
The client binary doesn't open any listening port.

Modern alternative is `ncat` / `openssl s_client` for TLS-aware
testing. `telnet` itself is harmless on a host with no telnetd
running.

### Fix
None recommended. If a future cleanup removes `telnet` from the
install list, `ncat` would be the right replacement to add.

### Patch commit
N/A.

---

## [INFO] pure-ftpd `AllowUserFXP yes`
**File:** aegir/conf/ftpd/pure-ftpd.conf  (line 246)
**Category:** misc
**Status:** INFO — verified acceptable

### Description
FXP (File eXchange Protocol) lets two FTP servers transfer files
between them on the client's instruction, without the data passing
through the client. Historically used in FTP-bounce attacks where
the attacker uses one server to scan or relay traffic toward
another.

pure-ftpd defends against bounce attacks by checking the source IP
of `PORT` commands matches the client IP (default behaviour, can't
be disabled). With `AllowAnonymousFXP no` (line 252) anonymous
sessions cannot trigger FXP at all, so the residual risk is
authenticated-user FXP only — bounded to operators who already have
credentials.

`AllowUserFXP yes` is acceptable in this configuration.

### Fix
None.

### Patch commit
N/A.

---

## [INFO] FTP listener is FTPS-only via `TLS 2`
**File:** aegir/conf/ftpd/pure-ftpd.conf  (line 418)
**Category:** misc (positive finding)
**Status:** INFO

### Description
```
TLS                          2
```

pure-ftpd's `TLS 2` setting refuses any non-encrypted FTP connection.
Anonymous access is disabled (`NoAnonymous yes` line 77), users are
chrooted to their home (`ChrootEveryone yes` line 20), and idle
sessions timeout at 15 minutes (`MaxIdleTime 15` line 103). The FTP
listener is functionally FTPS-only.

Recorded as a positive finding to balance the audit's general
attitude toward FTP as a deprecated protocol — BOA's FTP is not in
that class.

### Fix
N/A.

### Patch commit
N/A.

---

## [INFO] MD5 usage in BOA is for non-security purposes only
**File:** BOA.sh.txt:421; aegir/tools/system/daily.sh:2457; aegir/tools/system/manage_solr_config.sh:544; aegir/tools/system/ip_access.sh:49; aegir/tools/backup/run/duplicity_bundle_installer.sh:19; aegir/tools/backup/run/duplicity_backup.sh:32; lib/settings/barracuda.sh.cnf:1329; lib/settings/octopus.sh.cnf:789
**Category:** misc
**Status:** INFO — verified acceptable

### Description
MD5 is used in 8 places across BOA. None are integrity checks; all
are convenience identifier derivations where MD5 collision-finding
doesn't help an attacker:

- `_encName = md5(hostname)` — license-file filename derivation. The
  attacker cannot pick the hostname; the hashed value is used purely
  as a stable filename for fetching `${_urlEnc}/${_encName}`.
- `_PlrID = md5(platform_path)` — cache-key for ctrl files.
- `CoreHS = md5(domain.user)` — Solr core ID.
- `_ssh_ips_hash = md5(ssh_ips_list)` — change-detection hash for
  the SSH allow-IP list; used as `if hash unchanged, skip
  expensive work`.

In each case, MD5 is being used as a *fast non-cryptographic hash*
for stable-name generation or change detection. Replacing with
SHA256 would not change the security properties (since neither was
ever about preimage or collision resistance) and would lengthen the
derived strings.

The one place BOA does integrity verification (Java/Corretto fetch at
`system.sh.inc:8038`) already uses SHA256.

### Fix
N/A.

### Patch commit
N/A.

---

## [INFO] `/tmp/virtwhat.$$.strace` predictable filename (cat-3 carry-over)
**File:** BOA.sh.txt:797; lib/functions/helper.sh.inc:718
**Category:** misc (cat-3 carry-over)
**Status:** INFO — same finding as cat 3

### Description
Cat-3 already flagged the `/tmp/virtwhat.$$.strace` predictable-name
issue (LOW, install-time only, no untrusted users present during
install). No change in this category's pass; recording the
cross-reference.

### Fix
Replace with `mktemp -t virtwhat.XXXXXX.strace`. One-line change.
Not actioned because the install context runs at machine bring-up
where no untrusted users exist yet.

### Patch commit
PENDING — folded into a future helper-script cleanup.

---

## [INFO] `chmod 4755 /usr/bin/mysecureshell` is intentional per upstream
**File:** lib/functions/system.sh.inc  (line 5751)
**Category:** misc
**Status:** INFO

### Description
BOA explicitly sets SUID on `/usr/bin/mysecureshell` (mode 4755). This
matches the upstream Debian package which ships the binary with the
same mode by default. The SUID bit is required by mysecureshell's
own design: it does chroot setup and env-var hardening as root, then
drops to the calling user's uid before exec'ing the user's session.

Not a finding; recording the chmod call's intent so it's not
re-flagged in future audits.

### Fix
N/A.

### Patch commit
N/A.

---

## [INFO] `chmod 4755 /bin/ping` is intentional (Linux uses CAP_NET_RAW; SUID is the fallback)
**File:** BOA.sh.txt:3723; lib/functions/system.sh.inc:5760
**Category:** misc
**Status:** INFO

### Description
BOA sets SUID on `/bin/ping`. On modern Debian/Devuan, ping uses
file capabilities (`cap_net_raw+ep`) by default — but capability
support varies across kernels/filesystems (some virtualisation
backends, NFS mounts), and SUID is the portable fallback. BOA picks
the conservative path.

Modern alternative: `setcap cap_net_raw+ep /bin/ping` and
`chmod 0755 /bin/ping`. Tighter, but only works where the underlying
FS supports xattrs/file-caps.

### Fix
None recommended for portability reasons. Could be revisited as part
of a Devuan/Debian-Bookworm-only cleanup.

### Patch commit
N/A.

---

## [INFO] BOA umask = 002 across the installer stack
**File:** lib/functions/system.sh.inc:9182,9186,9188
**Category:** misc
**Status:** INFO — by BOA design

### Description
BOA sets `umask 002` system-wide (in `/etc/profile`, `/etc/pam.d/login`,
and `/var/www/.profile`). This means newly created files default to
mode 0664 and dirs to 0775 — i.e., **group-write enabled**.

Combined with the BOA convention of `chown user:users` on many
tenant-area files, this means files end up writable by every member
of the `users` group. On a multi-tenant BOA host every tenant FTP
account is in `users`, so umask 002 + `chown :users` = cross-tenant
writability on those files.

This is the BOA tenant-shared-group model and is by design. Adam
confirmed the model in category 1 ("users have access only to limited
shell account... never have access to Aegir system user"). The
practical exposure is bounded by what BOA puts into `:users` files
(typically per-tenant directories that wouldn't be cross-tenant in
the first place).

Not actionable in this audit. Worth a separate conversation if BOA's
group model ever evolves toward per-tenant-only group membership
(which would let umask 002 stay while removing the shared-group
side-effect).

### Fix
N/A — by BOA design.

### Patch commit
N/A.

---

## [INFO] Cipher hardening in BOA-shipped Nginx already excludes RC4, EXP, DES, MD5, PSK
**File:** lib/functions/nginx.sh.inc  (line 158, 890)
**Category:** misc (positive finding)
**Status:** INFO

### Description
The `_force_advanced_nginx_config` cipher list excludes the
historically broken cipher classes:

```
!aNULL :!eNULL :!EXPORT :!DES :!RC4 :!MD5 :!PSK :!aECDH
:!EDH-DSS-DES-CBC3-SHA :!EDH-RSA-DES-CBC3-SHA :!KRB5-DES-CBC3-SHA
:!ECDHE-ECDSA-AES128-SHA256 :!ECDHE-ECDSA-AES256-SHA384
```

The `UI_CIPHER` line in csf.conf line 2096 still references RC4,
but the CSF UI is disabled (`UI = "0"`, cat 7 finding) so the
cipher line is inert.

### Fix
N/A.

### Patch commit
N/A.

---

## [INFO] Password-generation RNG uses both `openssl rand` and `shuf -zer`
**File:** lib/functions/sql.sh.inc:1210,1668; aegir/tools/system/manage_ltd_users.sh:705,713; lib/functions/satellite.sh.inc:2470,3354,3631
**Category:** misc
**Status:** INFO — minor preference, not a finding

### Description
Password generation uses two RNG paths in different branches:

- `openssl rand -base64 64 | tr -d '\n'` — CSPRNG via OpenSSL. Strong.
- `shuf -zer -n64 {A..Z} {a..z} {0..9} % @ | tr -d '\0'` — GNU
  `shuf`, which uses `random_r()` glibc PRNG seeded from `/dev/urandom`.
  Seed has 256 bits of entropy; subsequent output is theoretically
  predictable from a single seen output, but the attacker would
  have to see the output to predict the next — and at that point
  they already have the credential they're trying to predict.

Both paths produce 64-character passwords. The openssl path is
stronger in principle; the shuf path is the fallback when randpass
or openssl is unavailable. Acceptable; mentioned only so a future
audit doesn't re-flag this.

### Fix
N/A.

### Patch commit
N/A.

---

## Cross-references to findings in earlier categories

- HTTPS mirror flip + `curl -k` / `wget --no-check-certificate`
  removal: **category 5**, commit `fbdfc862d`.
- `chmod 777 /data /data/disk /data/conf` transient install-time
  window: **category 3**, INFO-only.
- `chmod 1777 /opt/tmp` sticky scratch root: **category 3**, commit
  `33394aa50` (Adam confirmed in PI mode).
- `chmod 1777 /var/tmp/fpm` opcache lockfile dir: **category 3**,
  commit `d11d7c99c`.
- `/var/log/php*` permissions: **category 3**, commit `d11d7c99c`.
- `/data/conf/arch/log` 0777 → 0755: **category 3**, commit
  `d11d7c99c`.
- mybackup queue-file shell injection: **category 4**, commit
  `ab01133e5`.
- mysql_cleanup/backup/cluster SQL-ident allowlist: **categories 5
  and 6**, commits `fbdfc862d` and `8dc47dbff`.
- /proc hidepid=2: **category 6**, commit `786849236`.

The miscellaneous category turned up no new actionable items — the
prior seven categories caught everything that warranted a patch.
The two LOW items here (Node curl|bash, predictable virtwhat
filename) are operator-deferred and audit-pass deferred respectively.
