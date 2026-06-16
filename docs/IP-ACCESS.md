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
  allow <server ip>;
  allow <each live SSH client ip>;
  allow <each listed ip>;
  deny all;
```

The per-site vhost pulls it via `include $server->include_path/ip_access/{uri}*`, so the
restriction applies to that site only. A site with no record has no fragment and is
unrestricted.

`/var/xdrago/ip_access.sh` is a **single global generator**. It runs one shared routine
over two kinds of context:

- the **master** (sqladmin proxy) — `/var/aegir/control/ip/access.txt` →
  `/var/aegir/config/includes/ip_access/`;
- every **Octopus instance** — `/data/disk/<oct>/static/control/ip/access.txt` →
  `/data/disk/<oct>/config/includes/ip_access/` (skipping the `arch` backup
  pseudo-user).

This replaces the older per-Octopus `nginx_ip_access_<oct>.sh` copies with one script.

## Anti-lockout

Every generated fragment always allows, regardless of the listed IPs:

- `127.0.0.1` — loopback;
- the server's own IP, from `/root/.found_correct_ipv4.cnf`;
- **every currently logged-in SSH client IP**, from `who --ips`.

So an admin working over SSH is added to every site's allow-list automatically and
cannot be shut out mid-change. The SSH set is part of the change-gate (below), so a new
admin session triggers a regenerate on the next pass.

## Control file format

```
# /data/disk/o1/static/control/ip/access.txt
intranet.example.com   203.0.113.10 203.0.113.11
staging.example.com    198.51.100.42
```

- One site per line: the site name, then space-separated IPv4 addresses.
- Invalid site names and malformed IPs are skipped with a logged warning; the rest of
  the line is still applied.
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
- **Schedule / serial** — `*/2` cron; `_fetch_versioned` serial **f91** in `BOA.sh.txt`
  (decrement on any change).

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

## Caveats

- **IPv4 only.** The validator accepts IPv4 addresses; IPv6 client restriction is not
  handled here.
- **No CIDR.** Records are individual addresses, not ranges.
- **realip dependency** — as above, IP allow-lists on CF-proxied sites are only
  meaningful once realip is active; otherwise the rule sees the edge.
- **Whole-site, not path-scoped.** The fragment guards the site's `location` it is
  included in; it is not a per-path ACL.
