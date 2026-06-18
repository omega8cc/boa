# AI bot policy (sysadmin)

BOA classifies AI crawlers, indexers and assistant fetchers by user-agent and applies
a default policy at the nginx layer, with a per-site opt-in/opt-out. Aggressive
scrapers and obvious probes are blocked outright; legitimate AI traffic is sorted into
classes that are each allowed or blocked by default and can be flipped per site.

This document covers the whole mechanism. Site operators who only need to turn a class
on or off for one site can read [AI-POLICY-USER.md](AI-POLICY-USER.md) instead — this
document is a superset of it.

## Classes and the default policy

Classification is by **distinctive UA token**, never a bare vendor name (so `GPTBot`
and `ChatGPT-User` land in different classes, and "ChatGPT" alone matches nothing).

| Class | `$is_ai_*` map | Example tokens | Default action |
|-------|----------------|----------------|----------------|
| Scrapers / bad bots | `$is_crawler` (pre-existing) | mass scrapers, download tools | **Hard block (444), always** |
| AI **training** | `$is_ai_training` | GPTBot, ClaudeBot, Claude-Web, anthropic-ai, CCBot, Bytespider, Amazonbot, AI2Bot, Diffbot, Meta-ExternalAgent, cohere-ai, omgili | **Blocked (444)**; per-site opt-in to **allow** |
| AI **search/index** | `$is_ai_search` | OAI-SearchBot, Claude-SearchBot, PerplexityBot, MistralAI-Index, YouBot, Google-CloudVertexBot | **Allowed + per-vendor aggregate rate-limit (1r/s)**; per-site opt-in to **block** |
| AI **user** (honest assistant fetch a user asked for) | `$is_ai_user` | ChatGPT-User, Claude-User, MistralAI-User, Meta-ExternalFetcher, Google-Agent | **Allowed + per-vendor aggregate rate-limit (2r/s)**; per-site opt-in to **block** |
| AI **user — evasive** (user-triggered but ignores robots.txt and evades blocks) | `$is_ai_evasive` | Perplexity-User | **Blocked (444)**; per-site opt-in to **allow** |
| AI **utility** | `$is_ai_utility` | OAI-AdsBot, DuckAssistBot, Google-Read-Aloud, Google-NotebookLM | **Allowed + per-vendor aggregate rate-limit (1r/s)**; per-site opt-in to **block** |
| **Forged** opt-out tokens | `$is_ai_forged` | Google-Extended, Applebot-Extended | **Hard block (444), always** |
| Secret-path probes | `$is_secret_path` | `.env` `.git` `.aws` `.ssh`, `*.json` creds, `settings.py`, … | **Hard block (444), always** |

The stance: block the worst offenders unconditionally, separate every real AI agent into
a class, and make each class flippable per site. Training and the **evasive** user-fetch
class are opt-**in** (off by default); search / user / utility are opt-**out** (on by
default).

`Google-Extended` and `Applebot-Extended` are **robots.txt directives, not real
crawlers** — they never appear as a live user-agent. A request carrying one as its UA is
therefore forged and is dropped unconditionally.

The **evasive** user-fetch class (`$is_ai_evasive`) is for agents that are nominally
user-triggered but ignore `robots.txt` and, when blocked, drop their declared UA and
rotate IPs/ASNs to slip past a UA rule — `Perplexity-User` is the current member
(Cloudflare de-listed it as a verified bot for exactly this). It is blocked by default,
but because the block is **by UA it is only best-effort**: once the agent abandons its UA
it looks like an ordinary browser and the maps (fail-open) let it through. The real
backstop for the rotating/undeclared traffic is the IDS/csf layer, not this policy — so
do not read a block here as a hard guarantee against Perplexity. The honest user-fetchers
(`$is_ai_user`) identify truthfully and stay allowed; the split keeps the gentle default
for them while denying the one agent that abuses it.

## Where it lives

Two template layers, both in the `provision` (Provision) codebase, render onto the box:

- **Central http config** — `http/Provision/Config/Nginx/server.tpl.php` renders the
  master nginx `http{}` block (under `/var/aegir`): the `$is_ai_*` / `$is_secret_path` /
  `$is_banned` maps, the realip block, the `ai_search` / `ai_user` / `ai_utility`
  `limit_req` zones, and the log format.
- **Per-vhost guards** — `http/Provision/Config/Nginx/Inc/vhost_include.tpl.php` renders
  each instance's `nginx_vhost_common.conf`, which carries the guard chain and the AI
  rate-limit in `location /`.

The per-site fragments that flip a class are written into each Octopus instance's own
`config/includes/ai_policy/` by `/var/xdrago/ai_policy.sh` (see
[Per-site control](#per-site-control)).

### Guard order (per request)

The vhost guard chain runs early in request processing, top to bottom:

```
if ($is_banned)      { return 444; }   # csf web-bans, realip-keyed (see Bans)
if ($is_secret_path) { return 444; }   # credential / dotfile probes
if ($is_ai_forged)   { return 444; }   # forged opt-out tokens

set $ai_train_block $is_ai_training;    # training composite:
if ($ai_train_allow) { set $ai_train_block ''; }   #   per-site opt-in clears it
if ($ai_train_block) { return 444; }    #   otherwise training is blocked

set $ai_evasive_block $is_ai_evasive;   # evasive user-fetch (Perplexity), same shape:
if ($ai_evasive_allow) { set $ai_evasive_block ''; }  #  per-site opt-in clears it
if ($ai_evasive_block) { return 444; }  #   otherwise evasive is blocked
```

Search / user / utility have **no global guard** — they are allowed by default, so a
per-site block is carried directly by the fragment as `if ($is_ai_search) { return 444; }`
(and likewise for user/utility). Training and evasive are the opposite: blocked by a
global composite guard, cleared per site by `$ai_train_allow` / `$ai_evasive_allow`. The
rate limit for the three allowed classes is applied in `location /` via
`limit_req zone=ai_search|ai_user|ai_utility`.

The rate-limit zones key on the **per-vendor** maps (`$ai_*_limit_key`): non-AI traffic
emits an empty key (not counted), and each in-class UA emits a constant unique to its
vendor. The zone therefore caps each vendor's **aggregate** rate across every source IP
and vhost — the right primitive for an assistant whose single prompt fans out over many
IPs, which a per-IP limit never catches — and gives each vendor its own bucket so one
cannot starve another. Each `$ai_*_limit_key` roster must track the matching `$is_ai_*`
class map; they are kept adjacent in `server.tpl.php` for that reason.

## Real client IP (realip)

Every guard above keys on `$remote_addr`. Behind Cloudflare the raw peer is a CF edge,
so nginx is configured to recover the real client:

```
real_ip_header    CF-Connecting-IP;
real_ip_recursive on;
include /data/conf/nginx_cloudflare_real_ip.c*;   # set_real_ip_from <CF ranges>
```

`/var/xdrago/cloudflare_realip.sh` fetches Cloudflare's published IPv4+IPv6 ranges into
that include (daily cron, and once at install time from `BOA.sh.txt` so a fresh box does
not wait for the cron). With it active, `$remote_addr` is the **real visitor** and
`$realip_remote_addr` is the edge. Enforcement and logging therefore bite the real
client even for CF-proxied sites; PHP is still fed the peer (`fastcgi_param REMOTE_ADDR
$realip_remote_addr`) so it keeps treating the edge as the proxy.

The empty-glob include (`*.c*`) means the config is valid before the ranges file exists,
so there is no chicken-and-egg at first boot.

## Bans (csf → nginx)

`/var/xdrago/nginx_deny.sh` mirrors csf's **web** bans into nginx (`*/2` cron):

- `csf.tempban` rows whose port is 80 or 443 (self-expiring, port-tagged), plus
- `csf.deny` lines tagged `Brute force Web Server` (csf-water's web escalation),

are written to `/data/conf/nginx_banned_ips.conf` as a `geo $remote_addr $is_banned`
set, which the first guard turns into a 444. Because it is realip-keyed it blocks the
real client even through Cloudflare, where an origin-level csf deny would be a no-op. SSH
and FTP bans are deliberately excluded — those stay purely csf's job.

## Per-site control

A site flips a class via a record in its Octopus instance's control file:

```
/data/disk/<oct>/static/control/ai/policy.txt
```

Record format — `<site>` followed by zero or more flags:

| Flag | Effect |
|------|--------|
| `train-allow` | `set $ai_train_allow 1;` — allow AI training for this site |
| `evasive-allow` | `set $ai_evasive_allow 1;` — allow the evasive user-fetch class (Perplexity) for this site |
| `search-block` | `if ($is_ai_search)  { return 444; }` — block AI search/index |
| `user-block` | `if ($is_ai_user)    { return 444; }` — block AI user fetchers |
| `utility-block` | `if ($is_ai_utility) { return 444; }` — block AI utility bots |

```
# /data/disk/o1/static/control/ai/policy.txt
news.example.com    train-allow
shop.example.com    search-block user-block
```

`/var/xdrago/ai_policy.sh` is a **single global generator** that loops every Octopus
instance under `/data/disk/<oct>` — real instances only, identified by the BOA-canonical
`tools/drush` marker, so the non-instance pseudo-dirs (`arch`, `all`, `legacy`, …) are
skipped. For each instance with an activated `policy.txt` it writes one
`config/includes/ai_policy/<site>.conf` per record — the exact path the satellite vhost
pulls via `include $server->include_path/ai_policy/{uri}*`. `$ai_train_allow` and
`$ai_evasive_allow` are both defaulted to `0` in the vhost template before that include,
so a site with no record keeps the global defaults. Removing a record prunes its fragment
on the next run.

## Generators, lock and serials

| Tool | Schedule | Writes | Serial |
|------|----------|--------|--------|
| `/var/xdrago/ai_policy.sh` | `*/2` | per-instance `config/includes/ai_policy/<site>.conf` | f97 |
| `/var/xdrago/ip_access.sh` | `*/2` | per-instance `config/includes/ip_access/<site>.conf` (see [IP-ACCESS.md](IP-ACCESS.md)) | f89 |
| `/var/xdrago/nginx_deny.sh` | `*/2` | `/data/conf/nginx_banned_ips.conf` | f99 |
| `/var/xdrago/cloudflare_realip.sh` | daily + install | `/data/conf/nginx_cloudflare_real_ip.conf` | f99 |

All four take a shared advisory lock `/run/boa_nginx_config.lock` (`flock -w 30`, then
skip and retry next tick) so their `configtest`+`reload` cycles never collide on the
same host nginx. Each one is a content change-gate → atomic write → `configtest` →
`reload`, with rollback to the last-good copy if `configtest` fails. Any change to a
serial-gated tool must decrement its `fNN` in `BOA.sh.txt` in the same commit.

## Verify

```bash
# realip ranges present and included
test -s /data/conf/nginx_cloudflare_real_ip.conf && head -1 /data/conf/nginx_cloudflare_real_ip.conf

# a site's generated AI fragment
cat /data/disk/o1/config/includes/ai_policy/news.example.com.conf

# class behaviour (run against a real vhost; -A sets the UA)
curl -sS -o /dev/null -w '%{http_code}\n' -A 'GPTBot/1.1'         https://site/    # 444 (training blocked)
curl -sS -o /dev/null -w '%{http_code}\n' -A 'OAI-SearchBot/1.0'  https://site/    # 200 (search allowed)
curl -sS -o /dev/null -w '%{http_code}\n' -A 'ChatGPT-User/1.0'   https://site/    # 200 (honest user fetch, per-vendor capped)
curl -sS -o /dev/null -w '%{http_code}\n' -A 'Perplexity-User/1.0' https://site/   # 444 (evasive, blocked by default)
curl -sS -o /dev/null -w '%{http_code}\n' -A 'Google-Extended'    https://site/    # 444 (forged)

service nginx configtest
```

For a full end-to-end runbook (deploy, realip, per-site policy, bans, rollback, the
shared lock) on a disposable VM, see [AI-POLICY-TESTING.md](AI-POLICY-TESTING.md).

## Caveats

- **UA tokens age.** Vendors add and rename agents; the maps are a point-in-time list
  (current as of this cycle). Re-check vendor crawler docs periodically and add tokens to
  the relevant `$is_ai_*` map in `server.tpl.php`. A missing token just means that agent
  falls through to ordinary handling — fail-open, not fail-closed.
- **`Google-Agent` is new (2026).** Google's user-triggered agentic fetcher (Project
  Mariner / Gemini) ignores `robots.txt` like `ChatGPT-User` and is classed as an honest
  user fetcher. It is matched as `Google-?Agent` to catch both documented spellings
  (`Google-Agent` and `GoogleAgent-…`). The token is still settling — re-confirm against
  Google's user-triggered-fetchers list and tighten the match if a collision ever appears.
- **Fan-out, not single fetch.** A "user" fetch is not necessarily one request: some
  assistant agents (notably `ChatGPT-User`, and `Meta-ExternalFetcher`) expand a single
  prompt into many requests spread across the vendor's published IP ranges. That is why
  the user/search/utility limits are keyed **per vendor (aggregate)**, not per IP — a
  per-IP cap never bites a distributed fan-out because each IP stays under the limit. If a
  class feels too tight or too loose, tune `rate=`/`burst=` in `server.tpl.php`; do not
  revert the key to `$binary_remote_addr`.
- **UA is forgeable; verify by IP for the agents that matter.** Classification here is by
  UA string alone, which a client can spoof. The vendors whose traffic matters publish
  signed IP-range feeds — OpenAI `https://openai.com/chatgpt-user.json` (and `gptbot.json`
  / `searchbot.json`), Anthropic `https://claude.com/crawling/bots.json`, Mistral
  `https://mistral.ai/mistralai-user-ips.json`. Gating the UA match on membership of the
  current feed (mirroring `cloudflare_realip.sh`) is the robust form and a sound phase-2;
  it is intentionally **not** in this cut.
- **Evasive agents defeat UA blocking.** `Perplexity-User` (the `$is_ai_evasive` class) is
  documented to drop its declared UA and impersonate Chrome-on-macOS, rotating IPs/ASNs,
  when blocked. Because the maps are fail-open, a block here — global or per-site — does
  **not** reliably stop it; once it abandons its UA it is ordinary browser traffic. That
  case belongs to the IDS/csf layer, not this policy. Note too that IP verification
  confirms genuine OpenAI/Anthropic traffic but will **not** make Perplexity blockable by
  IP, since it rotates outside its own published range.
- **Amazonbot** is classified as `training`. It is a bulk crawler that feeds Amazon's
  models; if a site wants Amazon indexing, move it to `utility` or allow it per site.
- **Secret-path breadth.** `config.json` / `key.json` are in the probe list because
  Drupal/Aegir never serve them at the web root. A hosted **decoupled** front-end that
  legitimately serves such a file would 444 — remove that token from `$is_secret_path`
  if it ever bites.
- **realip window.** Until `cloudflare_realip.sh` has run once, `$remote_addr` is the CF
  edge: AI enforcement still works (it keys on the UA, not the IP), but the ban map and
  any IP allow/deny see the edge. The install-time invocation closes this on a normal up.
- **Rate limits** (`1–2 r/s` with burst from the zone) are deliberately gentle; tune the
  `rate=`/`burst=` in `server.tpl.php` if a class is too loose or too tight in practice.
