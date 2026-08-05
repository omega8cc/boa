# Per-site IP access (sysadmin)

`ip_access` restricts an individual site to a list of allowed IP addresses at the nginx
layer — everything not on the list gets a 403, with the loopback, the server itself and
any live SSH client always allowed so the box can never lock itself (or you) out.

Site operators who only need to allow a set of IPs for one site can read
[IP-ACCESS-USER.md](IP-ACCESS-USER.md) — this document is a superset of it.

## Mechanism

A control file of `<site>  <ip…>` records drives a generator that writes one nginx
include per site:

```
<site>.conf:
  allow 127.0.0.1;
  allow ::1;
  allow <server ip>;
  allow <each live SSH client ip>;
  allow <each listed ip / subnet>;
  deny all;
```

Each listed entry may be an **IPv4 or IPv6 address, with an optional CIDR prefix** — this is
a pure nginx `allow`/`deny` layer (no csf involvement), and the nginx access module takes all
four forms.

The per-site vhost pulls it via `include $server->include_path/ip_access/{uri}.conf*`, so the
restriction applies to that site only. A site with no record has no fragment and is
unrestricted.

`/var/xdrago/ip_access.sh` is a **single global generator**. It runs one shared routine
over two kinds of context:

- the **master** (sqladmin proxy) — `/var/aegir/control/ip/access.txt` →
  `/var/aegir/config/includes/ip_access/`;
- every **Octopus instance** — `/data/disk/<oct>/static/control/ip/access.txt` →
  `/data/disk/<oct>/config/includes/ip_access/`. Real instances only, identified by the
  BOA-canonical `tools/drush` marker, so the non-instance pseudo-dirs (`arch`, `all`,
  `legacy`, …) are skipped.

This replaces the older per-Octopus `nginx_ip_access_<oct>.sh` copies with one script.

## Anti-lockout

Every generated fragment always allows, regardless of the listed IPs:

- `127.0.0.1` and `::1` — loopback;
- the server's own IPv4, from `/root/.found_correct_ipv4.cnf` (BOA tracks no server IPv6);
- **every established inbound SSH client IP**, read from `netstat -tn` (peers on an
  `ESTABLISHED` connection to any local SSH port — the union of `22`, the cnf `_SSH_PORT`
  and every port the live sshd config serves, so the harvest follows a custom port yet can
  never go dark on a default-port box), **IPv4 or IPv6** — the peer address is taken by
  stripping the trailing `:port`, so both families are harvested, and each is validated
  before it reaches an `allow` line. BOA uses `netstat` here, not `who --ips`, because
  `who --ips` is unavailable on Excalibur and newer.

So an admin working over SSH is added to every site's allow-list automatically and
cannot be shut out mid-change. The SSH set is part of the change-gate (below), so a new
admin session triggers a regenerate on the next pass.

## Control file format

```
# /data/disk/o1/static/control/ip/access.txt
intranet.example.com   203.0.113.10 203.0.113.0/24 2001:db8::/32
staging.example.com    198.51.100.42 2001:db8:1::1
```

- One site per line: the site name, then space-separated allowed addresses. Each may be an
  **IPv4 or IPv6 address, with an optional CIDR prefix** (`/24`, `/32`, `/64`, `/128`, …).
- Invalid site names and malformed addresses are skipped with a logged warning; the rest of
  the line is still applied. The validator is a strict subset of what nginx accepts, so a
  validated entry never breaks the box-wide configtest.
- `#` comments and blank lines are ignored.

## Generator behaviour

- **Change-gate** — a context regenerates only when its control file's mtime advanced
  **or** the host's SSH-client set changed (so newly logged-in admins propagate). No
  change → no write, no reload.
- **Pruning** — removing a site from the control file deletes its fragment on the next
  run, lifting the restriction (the site becomes open again).
- **Safety** — per context: back up the current fragments, regenerate atomically,
  `service nginx configtest`, then `reload`; on a failed configtest or reload, restore
  the last-good backup and reload. The whole script holds the shared
  `/run/boa_nginx_config.lock` (`flock -w 30`) so it never overlaps `ai_policy` /
  `nginx_deny` / `cloudflare_realip`.
- **Schedule / serial** — `*/2` cron; serial-gated via `_fetch_versioned` in `BOA.sh.txt`
  (decrement its `fNN` on any change).

## Interaction with realip

The `deny`/`allow` rules key on `$remote_addr`. With Cloudflare realip active (see
[AI-POLICY.md](AI-POLICY.md#real-client-ip-realip)) `$remote_addr` is the **real visitor
IP**, so the allow-list must contain the visitor's real public IP — which is what an
operator naturally enters. Without realip active (the brief pre-cron window), a
CF-proxied site would see the CF edge instead, and a real-IP allow-list would not match;
the install-time realip activation closes that window on a normal box.

## Verify

```bash
# a site's generated allow/deny
cat /data/disk/o1/config/includes/ip_access/intranet.example.com.conf

# from a non-allowed IP -> 403; from a listed IP (or over the server/SSH) -> 200
curl -sS -o /dev/null -w '%{http_code}\n' https://intranet.example.com/

service nginx configtest
```

For a full end-to-end runbook on a disposable VM, see
[AI-POLICY-TESTING.md](AI-POLICY-TESTING.md) (Phase 4 covers IP access).

## IPv4, IPv6 and CIDR

This is a **pure nginx `allow`/`deny` layer** — it keys on the recovered client IP at the
web tier and does not touch csf. So it takes **both address families and subnets**: an entry
may be an IPv4 or IPv6 address, singly or as a CIDR range (`203.0.113.0/24`, `2001:db8::/32`,
…). The validator is a strict subset of what the nginx access module accepts, so a
validated entry can never break the box-wide configtest. Note this is independent of csf:
adding an IPv6 rule here restricts the site at nginx but does **not** add a host-firewall
rule (csf remains a separate layer).

## Caveats

- **realip dependency** — IP allow-lists on CF-proxied sites are only meaningful once realip
  is active; otherwise the rule sees the edge.
- **Whole-site, not path-scoped.** The fragment guards the site's `location` it is included
  in; it is not a per-path ACL. For a path-scoped variant limited to `/user` + `/admin`, see
  [USER-ADMIN-ACCESS.md](USER-ADMIN-ACCESS.md).
- **Server IPv6 anti-lockout** — BOA tracks only the server's IPv4 (`/root/.found_correct_ipv4.cnf`),
  so an IPv6-only box's own address is not auto-allowed; loopback (`::1`), live IPv6 SSH peers,
  and any listed IPv6 entries still are.
