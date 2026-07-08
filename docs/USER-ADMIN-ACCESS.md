# Per-site /user + /admin IP access (sysadmin)

`user_admin_access` restricts a site's **login and admin surface** — the Drupal `/user`
and `/admin` URIs — to a list of allowed addresses at the nginx layer. A request to those
paths from any other address gets a 403; the rest of the site stays public. It is the
path-scoped counterpart to whole-site [IP-ACCESS.md](IP-ACCESS.md): same control-file
shape and generator discipline, but it guards only the admin surface and, being a pure
nginx `allow`/`deny` layer with **no csf involvement**, it accepts IPv4 **and** IPv6,
single addresses **and** CIDR subnets.

Site operators who only need to lock down `/user` and `/admin` for one site can read
[USER-ADMIN-ACCESS-USER.md](USER-ADMIN-ACCESS-USER.md) — this document is a superset of it.

## Mechanism

A control file of `<site>  <ip|cidr…>` records drives a generator that writes two nginx
includes per site into that Octopus instance's `config/includes/`:

```
user_admin_access_map/<site>.conf   (http scope)
  geo $ua_ip_ok_<hash>  { default 0; 127.0.0.1 1; ::1 1; <allowed…> 1; }
  map $uri  $ua_u_<hash>    { default 0; ~*^/+(?:user|admin)(?:/|$) 1; }
  map "$ua_u_<hash>$ua_ip_ok_<hash>" $ua_deny_<hash> {
    default 0; "10" 1;
  }

user_admin_access/<site>.conf       (server scope)
  if ($ua_deny_<hash>) { return 403; }
```

`$ua_deny_<hash>` is 1 only when a `/user`-or-`/admin` request (matched on the clean `$uri`)
arrives from an address the `geo` did not allow. BOA enforces Drupal clean URLs, so those
paths always arrive in `$uri` — which nginx percent-decodes and normalises (collapsing
`/./` and, under the default `merge_slashes on`, `//`); the `^/+` anchor also catches a
multi-slash `//admin` even if a vhost ever disabled `merge_slashes`. The legacy `?q=admin`
query form is not a clean path (not served by default on BOA) and is deliberately not
matched here — `$arg_q` cannot be reliably gated at the nginx layer (nginx neither
percent-decodes it nor de-duplicates it the way Drupal reads `$_GET['q']`), so a partial
match there would be a bypassable false control. `<hash>` is a short digest of the site
name, so each site's variables are unique in the shared `http{}`.

The per-site vhost pulls the http-scope fragment **once at the file head** via
`include $server->include_path/user_admin_access_map/{uri}.conf*` and the server-scope
fragment inside **every serving server block** (co-located with `ip_access`) via
`include $server->include_path/user_admin_access/{uri}.conf*`. Both are wildcard includes,
so a site with no fragment is a no-op — the feature is strict opt-in. The `.conf*` anchor
(not a bare `{uri}*`) matters: a bare glob would also match a longer site whose name extends
this one (`example.com` vs `example.com.au`), pulling that site's fragment into this vhost
and wrongly applying its restriction here. Regular sites carry their `:80` and `:443` blocks
in one vhost file; the geo/map is emitted once and referenced from both (nginx resolves
map/geo variables across the whole `http{}` regardless of textual order, so the `:443`
block's forward reference is fine).

`/var/xdrago/user_admin_access.sh` is a **single global generator** over every real
**Octopus instance** — `/data/disk/<oct>/static/control/ip/user_admin.txt` →
`/data/disk/<oct>/config/includes/user_admin_access{,_map}/`. Instances are identified by
the BOA-canonical `tools/drush` marker, so the non-instance pseudo-dirs (`arch`, `all`,
`legacy`, …) are skipped. Unlike `ip_access` there is no master/sqladmin context: the
hostmaster front-end has its own vhost, out of scope here.

## Anti-lockout

Every generated `geo` always allows, regardless of the listed addresses:

- `127.0.0.1` and `::1` — loopback;
- the server's own IP, from `/root/.found_correct_ipv4.cnf`;
- **every established inbound SSH client IPv4**, read from `netstat -tn` (peers on an
  `ESTABLISHED` `:22` connection) — the same source `ip_access` uses, because `who --ips`
  is unavailable on Excalibur and newer.

So an admin working over SSH is added to every site's allow-list automatically and cannot
be shut out of `/admin` mid-change. The SSH set is part of the change-gate, so a new admin
session triggers a regenerate on the next pass. Auto anti-lockout is IPv4 only (an admin's
IPv6 workstation is honoured when listed in the control file).

## Control file format

```
# /data/disk/o1/static/control/ip/user_admin.txt
intranet.example.com   203.0.113.10 203.0.113.0/24 2001:db8::/32
staging.example.com    198.51.100.42 2001:db8:1::1
```

- One site per line: the site name, then space-separated allowed addresses.
- Each address may be an **IPv4 or IPv6 address, with an optional CIDR prefix** (`/24`,
  `/32`, `/64`, `/128`, …). A bare address is a single host.
- Invalid site names and malformed addresses are skipped with a logged warning; the rest
  of the line is still applied. The validator is a strict subset of what nginx accepts, so
  a validated entry never breaks configtest.
- `#` comments and blank lines are ignored.

## Generator behaviour

- **Change-gate** — a context regenerates only when its control file's mtime advanced, the
  host's SSH-client set changed, or the emitted-directive version bumped. No change → no
  write, no reload.
- **Pruning** — removing a site from the control file deletes both its fragments on the
  next run, lifting the restriction (the admin surface becomes open again).
- **Safety** — per context: back up the current fragments, regenerate atomically,
  `service nginx configtest`, then `reload`; on a failed configtest or reload, restore the
  last-good backup and reload. The whole script holds the shared
  `/run/boa_nginx_config.lock` (`flock -w 30`) so it never overlaps `ip_access` /
  `ai_policy` / `nginx_deny` / `cloudflare_realip`.
- **Schedule / serial** — `*/2` cron; serial-gated via `_fetch_versioned` in `BOA.sh.txt`
  (decrement its `fNN` on any change).

## Interaction with realip

The `geo` keys on `$remote_addr`. With Cloudflare realip active (see
[AI-POLICY.md](AI-POLICY.md#real-client-ip-realip)) `$remote_addr` is the **real visitor
IP**, so the allow-list must contain the visitor's real public IP — which is what an
operator naturally enters. Without realip active (the brief pre-cron window), a CF-proxied
site would see the CF edge instead; the install-time realip activation closes that window
on a normal box.

## Verify

```bash
# a site's generated gate
cat /data/disk/o1/config/includes/user_admin_access_map/intranet.example.com.conf
cat /data/disk/o1/config/includes/user_admin_access/intranet.example.com.conf

# from a non-allowed IP: /admin and /user -> 403, everything else -> 200
curl -sS -o /dev/null -w '%{http_code}\n' https://intranet.example.com/admin
curl -sS -o /dev/null -w '%{http_code}\n' https://intranet.example.com/

service nginx configtest
```

## Relationship to whole-site ip_access

`ip_access` and `user_admin_access` are independent and compose: a site may use either,
both, or neither. `ip_access` denies the **whole** site to anyone off its list;
`user_admin_access` denies only **`/user` + `/admin`**. Both are pure nginx `allow`/`deny`
layers (no csf), both now take **IPv4 + IPv6 + CIDR**, both key on `$remote_addr`, and both
auto-allow the loopback, server and live SSH admin so you cannot lock yourself out — the only
difference is scope (whole-site vs the admin surface).

## Caveats

- **Admin surface only.** The gate covers the `/user` and `/admin` URL paths (and their
  sub-paths). It is not a whole-site ACL — use `ip_access` for that.
- **Clean URLs only.** BOA enforces Drupal clean URLs, so `/user` and `/admin` arrive as the
  real `$uri`, which the match is keyed on (nginx decodes/normalises `$uri`, so the match is
  encoding- and multi-slash-safe). The legacy `?q=admin` query form is not gated at the
  nginx layer — it is not served by default on BOA, and `$arg_q` cannot be reliably matched
  there. This matches BOA's existing nginx admin guard (`location ^~ /admin`), which likewise
  keys on the clean path; Drupal's own authentication remains the control for that vector.
- **Defence in depth, not the sole control.** Drupal's own login and permission checks
  still apply; this layer narrows *who can reach* the login/admin surface at the edge.
- **realip dependency** — as above, allow-lists on CF-proxied sites are only meaningful
  once realip is active; otherwise the rule sees the edge.
- **Octopus sites only.** The hostmaster front-end uses a separate vhost and is not covered.
