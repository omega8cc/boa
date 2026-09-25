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
multi-slash `//admin` even if a vhost ever disabled `merge_slashes`.

The legacy `?q=admin`
query form is not a clean path (not served by default on BOA) and is deliberately not
matched here — `$arg_q` cannot be reliably gated at the nginx layer (nginx neither
percent-decodes it nor de-duplicates it the way Drupal reads `$_GET['q']`), so a partial
match there would be a bypassable false control. `<hash>` is a short digest of the site
name, so each site's variables are unique in the shared `http{}`.

### Grav 2 and Textpattern sites

Both keep their admin surface outside `/user` and `/admin`, and both vhost templates
include the two fragments unchanged, so the generator writes their `$uri` map itself, for a
site whose platform root positively reads as one of them:

```
Grav 2        ~*^/+admin(?:/|$) 1;
              ~*^/+api(?:/|$) 1;        (unless the record carries api-open)
Textpattern   ~*^/+(?:user|admin)(?:/|$) 1;
              ~*^/+txpadmin(?:/|$) 1;
```

Grav's `/user` is its public theme and media tree (`/user/themes/…`, served to every
visitor, with the account and config folders already refused), so a Grav map gates `/admin`
only. No variable is added and no include changes; the emitted-directive version bump
regenerates every fragment of an instance with a control file on the next pass.

- **Why `/api` on Grav 2.** Admin2 at `/admin` is only a shell; every login, account, page,
  media and configuration operation runs through the API plugin at `/api/v1` (JWT from
  `POST /api/v1/auth/token`, or an API key). A list that stopped at `/admin` restricted the
  shell and left the data surface open. The whole `/api` route is matched, not `/api/v1`,
  so a later version segment is covered.

  The `(?:/|$)` tail holds the match to the plugin's
  real routes: the plugin wakes on any path that merely begins with `/api`, but a lookalike
  such as `/apix/v1/auth/token` (same length as the real base or not) lands on no endpoint
  and only draws the plugin's own 401, so its pre-authentication layer, and nothing behind
  it, stays reachable on those paths. A language prefix needs no arm: on a multi-language
  capsule `/en/admin` and `/en/api/v1/…` are plain 404s.
- **The prefix is fixed at the plugin's default.** The route is a per-site plugin setting
  (`route: /api`), and the generator deliberately does not read it: that would mean root
  parsing tenant-written YAML on every pass, across the site config and its per-host
  environment overlays. A site that renames the route moves its API out from under the list.
- **`api-open`.** A site that serves a deliberately public headless API adds the keyword to
  its record; `/admin` stays on the list and `/api` stays public. The keyword is
  case-insensitive, means nothing outside a Grav record and is accepted silently there.
- **Detection** reads the platform root from the instance's own drush alias
  (`<oct>/.drush/<site>.alias.drushrc.php`, written by the backend, never by the tenant) and
  applies the shape test the nightly and the Solr agent share — provision's platform
  detection plus the Drupal negatives (`core/`, `modules/system/system.module`,
  `includes/bootstrap.inc`). Every doubt (no alias, a root that does not resolve, an unknown
  shape) leaves the site with the plain `/user` + `/admin` line: a miss never widens what a
  site matches.

The per-site vhost pulls the http-scope fragment **once at the file head** via
`include $server->include_path/user_admin_access_map/{uri}.conf*` and the server-scope
fragment inside **every serving server block** (co-located with `ip_access`) via
`include $server->include_path/user_admin_access/{uri}.conf*`. Both are wildcard includes,
so a site with no fragment is a no-op — the feature is strict opt-in. The `.conf*` anchor
(not a bare `{uri}*`) matters: a bare glob would also match a longer site whose name extends
this one (`example.com` vs `example.com.au`), pulling that site's fragment into this vhost
and wrongly applying its restriction here.

Regular sites carry their `:80` and `:443` blocks
in one vhost file; the geo/map is emitted once and referenced from both (nginx resolves
map/geo variables across the whole `http{}` regardless of textual order, so the `:443`
block's forward reference is fine).

`/var/xdrago/user_admin_access.sh` is a **single global generator** over every real
**Octopus instance** — `/data/disk/<oct>/static/control/ip/user_admin.txt` →
`/data/disk/<oct>/config/includes/user_admin_access{,_map}/`. Instances are identified by
the BOA-canonical `tools/drush` marker, so the non-instance pseudo-dirs (`arch`, `all`,
`legacy`, …) are skipped. Unlike `ip_access` there is no master/sqladmin context: the
master's hostmaster front-end has its own vhost, out of scope here.

An instance's control panel is covered: its HTTPS proxy in `pre.d` loads the panel's map
and includes its fragment, and judges the real visitor there (see IP-ACCESS.md).

## Anti-lockout

Every generated `geo` always allows, regardless of the listed addresses:

- `127.0.0.1` and `::1` — loopback;
- the server's own IPv4, from `/root/.found_correct_ipv4.cnf` (BOA tracks no server IPv6);
- **every established inbound SSH client IP (IPv4 or IPv6)**, read from `netstat -tn` (peers
  on an `ESTABLISHED` connection to any local SSH port — the union of `22`, the cnf
  `_SSH_PORT` and every port the live sshd config serves, so the harvest follows a custom
  port yet can never go dark on a default-port box; the peer address is taken by stripping
  the trailing `:port`, so both families are harvested) — the same source `ip_access` uses, because
  `who --ips` is unavailable on Excalibur and newer.

So an admin working over SSH — over IPv4 or IPv6 — is added to every site's allow-list
automatically and cannot be shut out of `/admin` mid-change. The SSH set is part of the
change-gate, so a new admin session triggers a regenerate on the next pass. Only the
server's own address is IPv4-only in the anti-lockout set (BOA tracks no server IPv6).

## Control file format

```
# /data/disk/o1/static/control/ip/user_admin.txt
intranet.example.com   203.0.113.10 203.0.113.0/24 2001:db8::/32
staging.example.com    198.51.100.42 2001:db8:1::1
```

- One site per line: the site name, then space-separated allowed addresses.
- A Grav 2 site's record may also carry the keyword `api-open` (see above).
- Each address may be an **IPv4 or IPv6 address, with an optional CIDR prefix** (`/24`,
  `/32`, `/64`, `/128`, …). A bare address is a single host.
- Invalid site names and malformed addresses are skipped with a logged warning; the rest
  of the line is still applied. The validator is a strict subset of what nginx accepts, so
  a validated entry never breaks configtest.
- `#` comments and blank lines are ignored.

## Generator behaviour

- **Change-gate** — a context regenerates only when its control file's mtime advanced, the
  host's SSH-client set changed, the emitted-directive version bumped, a listed site's CMS
  kind changed, or the front state or a listed site's server names changed (see below). The
  kind is baked into the fragment, so a record written before its Grav or Textpattern site
  exists picks up the extra line on the first pass after the site appears, with no edit to
  the control file. No change → no write, no reload.
- **Pruning** — removing a site from the control file deletes both its fragments on the
  next run, lifting the restriction (the admin surface becomes open again).
- **Safety** — per context: back up the current fragments, regenerate atomically,
  `service nginx configtest`, then `reload`; on a failed configtest or reload, restore the
  last-good backup and reload. The last-good archive is proved readable before the live fragments are deleted: an
  unreadable one leaves the fragments on disk alone and prints an `ALRT:` line naming the
  control file to fix, and a freshly written last-good that does not verify is removed.

  On a
  replication standby whose web tier is held, the fragments are written and the change-gate
  markers advance, but the reload and the revert are both skipped until promotion. The whole script holds the shared
  `/run/boa_nginx_config.lock` (`flock -w 30`) so it never overlaps `ip_access` /
  `ai_policy` / `nginx_deny` / `cloudflare_realip`.
- **Schedule / serial** — `*/2` cron; serial-gated via `_fetch_versioned` in `BOA.sh.txt`
  (decrement its `fNN` on any change).

## HTTPS through the wildcard SSL front

A site without a certificate of its own is served over HTTPS by the wildcard SSL front
(`nginx_wild_ssl.conf`), which proxies to the site's port-80 vhost. There the peer is always
`127.0.0.1`, which the anti-lockout admits, so the vhost fragments alone cannot hold on that
path.

The generator therefore also writes a front copy of every listed site into
`user_admin_access_front/`. `<site>.http.conf` holds its own `geo`, the same `$uri` map (the
Grav and Textpattern lines included) and a `$host` map of the site's server names, aliases
included; `<site>.srv.conf` holds the `403`. The front includes both and judges the real
visitor.

A name goes into the `$host` map only when it is a plain hostname of at most 174 bytes that
no other rendered vhost on the box also serves. A wildcard alias, or a name another instance
carries too, stays out, so the front never applies one site's list to another site's visitors.

Copies are written only once the deployed front carries their include lines (a barracuda
upgrade updates it), and only for a site with a rendered vhost. A deleted control file
changes nothing, on HTTP or HTTPS (a deletion does not travel to a mirror or a migration
target, so it could only ever lift one box); to lift, remove a site's line or empty the
file.

The copies still follow their sites' names then: a new alias is covered, a name that
moved to another site is released, and a site with no name of its own left keeps an inert
copy.

They share the instance's
change-gate and configtest, but are never backed up: a failed configtest or reload drops
them rather than restoring an older set, which could still claim a name that has since moved
to another site. A site with its own certificate has its own `:443` server block, which
includes the vhost fragments directly and never passes through the front.

A site whose control file was deleted before the front copies existed gets one written from
its frozen map, so HTTPS applies the list and paths HTTP already applies.

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
  sub-paths) on Drupal, Backdrop and Textpattern; Grav gates `/admin` (and `/api`). The
  match is anchored at the start of the path, so a multilingual site's language-prefixed
  forms (`/de/user`, `/pt-br/admin`) are not covered. A prefix pattern was weighed and
  left out: it would also gate a parent site's subdirectory sites (`/pl/user`), API login
  endpoints (`/api/user/login`) and content paths shaped like a prefix. It is not a
  whole-site ACL — use `ip_access` for that.
- **A frozen list keeps its paths.** An instance whose control file was deleted keeps
  every site's fragments as they were: a Grav map written before the Grav `/admin` line
  keeps the plain `/user` + `/admin` line, theme assets included, until the control file
  exists again.
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
- **Octopus instances only**: their sites and their control panel. The master's hostmaster
  front-end uses a separate vhost and is not covered.
