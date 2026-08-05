# Testing the AI policy, realip, per-site control and bans (disposable VM)

End-to-end verification checklist for the whole edge-policy stack: AI bot classification,
Cloudflare realip, per-site AI policy, per-site whole-site IP access and per-site
`/user`+`/admin` IP access (both IPv4/IPv6/CIDR), and the web-ban mirrors — the csf→nginx
IPv4 mirror and the nginx-native IPv6 ban. Intended for a throwaway VM where you can ban
yourself and break things freely.
Mechanics are documented in [AI-POLICY.md](AI-POLICY.md) and [IP-ACCESS.md](IP-ACCESS.md);
this is the runbook to confirm they behave on a real box.

## Automated quick-check (start here)

Most of this runbook is automated by **`edgetest`**, a command BOA installs in your PATH
(`/opt/local/bin/edgetest`). Run it first — it prints a plain `PASS`/`FAIL`/`WARN` line per
check and a summary, so you can see at a glance whether the critical pieces work, then dip
into the manual phases below only where you want to go deeper or where a check needs a
second host. `edgetest --help` lists the options.

**Run it on the box that HOSTS the site.** In its default (local) mode `edgetest` probes the
**local** nginx (`--resolve …:127.0.0.1`) and inspects local config, so the site must live on
the box you run it from; run elsewhere it warns and skips the local checks. To test a site on
**another** box — or to check ip_access from a given vantage — use `--remote`, which hits the
live site over the network from this box's IP.

```bash
# local: read-only checks (run ON the host serving <SITE>): presence, realip config,
# AI UA matrix, rate-limiting, ban wiring, fragments, regression spot-checks
edgetest --site <SITE> --oct <OCT>

# local + state-changing proofs (realip+ban bite, per-site AI toggles incl. the
# evasive-allow opt-in, ip_access validation, idempotence) — each self-cleans;
# run on a DISPOSABLE VM, as root
edgetest --site <SITE> --oct <OCT> --full

# remote: probe the LIVE site from this box's IP (real DNS) — AI policy + whether
# this box is ip_access-allowed. Run from a whitelisted box (expect allowed) and a
# non-whitelisted one (expect a 403 ip_access deny) to verify per-site IP access.
edgetest --site <SITE> --remote
```

It exits `0` when every critical check passes, non-zero otherwise. It treats a **5xx**
(backend/upstream error — e.g. a proxied 502) and a **403** (ip_access deny) as *inconclusive*
(`WARN`), not as a policy result. **HTTPS is not assumed** — it probes https and falls back to
http if https isn't cleanly served (a test VM with no real SSL behind a self-signed proxy);
force a scheme with `--http` / `--https`. What it does **not** automate (do these manually from the
phases below): the realip rewrite seen from a real external client, and the `configtest`
rollback backstop. The manual phases remain the source of truth for those.

## Conventions

Run each generator **manually** after editing a control file — it executes immediately and
echoes what it did, which is deterministic, instead of waiting for the `*/2` cron:

```bash
bash /var/xdrago/ip_access.sh
bash /var/xdrago/user_admin_access.sh
bash /var/xdrago/ai_policy.sh
bash /var/xdrago/nginx_deny.sh
bash /var/xdrago/nginx_deny6.sh
bash /var/xdrago/cloudflare_realip.sh
```

Placeholders: `<SITE>` = a real vhost on the box, `<OCT>` = its Octopus instance (e.g.
`o1`), `<TESTIP>` = a throwaway IP, `<CLIENTIP>` = the address your test machine reaches
the VM from.

Two things to keep straight so you don't read a false negative:

- **Rate-limit throttling returns `444`, not `503`** — the templates set
  `limit_req_status 444`, so a throttled request closes the connection just like the hard
  guards (training/forged/secret-path/banned). Tell them apart by behaviour, not status: a
  guard blocks *every* request of a class, whereas the rate limit lets a few through (`200`)
  and `444`s only the excess in a burst.
- **realip only rewrites `$remote_addr` when the request's peer is inside a
  `set_real_ip_from` range.** A direct hit from your laptop is not a CF edge, so the CF
  tests below first add `<CLIENTIP>` to the trusted set.

## Phase 0 — Deploy and presence

- [ ] Run the upgrade that ships this code (`barracuda up-<tier> system`); finishes clean.
- [ ] Tools present: `ls -l /var/xdrago/{ip_access,user_admin_access,ai_policy,nginx_deny,nginx_deny6,cloudflare_realip}.sh`
- [ ] Crontab has them (all `*/2` except cloudflare_realip daily):
      `crontab -l | grep -E 'ip_access|user_admin_access|ai_policy|nginx_deny6?|cloudflare_realip'`
- [ ] `service nginx configtest` → OK; nginx running.

## Phase 1 — realip foundation

- [ ] Ranges file written at install: `head /data/conf/nginx_cloudflare_real_ip.conf`
      shows `set_real_ip_from <CF v4 + v6 CIDRs>;`
- [ ] Central config carries the directives:
      `nginx -T 2>/dev/null | grep -E 'real_ip_header|set_real_ip_from' | head`
- [ ] **Prove realip rewrites `$remote_addr`:**
  1. Direct hit (realip inactive): `curl -s -o /dev/null https://<SITE>/` → access log host
     field is your real `<CLIENTIP>`.
  2. Trust your client temporarily:
     `echo "set_real_ip_from <CLIENTIP>;" >> /data/conf/nginx_cloudflare_real_ip.conf && service nginx reload`
  3. `curl -H 'CF-Connecting-IP: 203.0.113.99' https://<SITE>/` → access log now shows
     `203.0.113.99` as `$remote_addr`. ✔ realip works.
- [ ] **Prove PHP still gets the peer, not the spoofed client** (anti-XFF-spoof): a one-line
      PHP page echoing `$_SERVER['REMOTE_ADDR']`, hit as in step 3 → REMOTE_ADDR is your
      real `<CLIENTIP>` (the peer), **not** `203.0.113.99`.
- [ ] **Cleanup:** remove the `set_real_ip_from <CLIENTIP>;` line you added + `service nginx
      reload`. (The daily cron won't revert it on its own — the change-gate sees CF's ranges
      unchanged — so remove it by hand.)

## Phase 2 — AI default policy

UA-keyed, so a direct hit is fine (no CF needed). Run each:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -A '<UA>' https://<SITE>/
```

"Allowed" below means **any non-444 response** — a real Drupal site may answer a given
UA/path with `200` or a `301` redirect; only a `444` (curl shows it as `000`) is a block.

- [ ] `GPTBot/1.1` (training) → **444**
- [ ] `Perplexity-User/1.0` (evasive) → **444** (blocked by default — see Phase 3 to opt in)
- [ ] `Google-Extended` (forged opt-out token as a UA) → **444**
- [ ] `OAI-SearchBot/1.0` (search) → **allowed** (200 or 301)
- [ ] `ChatGPT-User/1.0` (user) → **allowed** (200 or 301)
- [ ] `Google-Agent/1.0` (user) → **allowed** (200 or 301)
- [ ] `OAI-AdsBot/1.0` (utility) → **allowed** (200 or 301)
- [ ] `Mozilla/5.0 (...)` (normal browser) → **200**
- [ ] Secret-path probe → **444**: `curl -s -o /dev/null -w '%{http_code}\n' https://<SITE>/.env`
      (also `/.git/config`, `/config.json`)
- [ ] **Rate-limit** (throttle = **444**, which curl shows as `000` because 444 closes the
      connection — `limit_req_status` is 444, not 503):
      `for i in $(seq 20); do curl -sk --http1.1 -o /dev/null -w '%{http_code} ' -A 'OAI-SearchBot/1.0' --resolve <SITE>:443:127.0.0.1 https://<SITE>/; done; echo`
      → first few `200`, then `000` (the 444 throttle; search zone = 1 r/s). Repeat with
      `Mozilla/...` → all `200` (browsers are never charged to an AI zone).

Tokens per class (any one matches the class):

| Class | Tokens |
|-------|--------|
| training | GPTBot, ClaudeBot, Claude-Web, anthropic-ai, CCBot, Bytespider, Amazonbot, AI2Bot, Diffbot, Meta-ExternalAgent, cohere-ai, omgili |
| search | OAI-SearchBot, Claude-SearchBot, PerplexityBot, MistralAI-Index, YouBot, Google-CloudVertexBot |
| user | ChatGPT-User, Claude-User, MistralAI-User, Meta-ExternalFetcher, Google-Agent |
| user (evasive) | Perplexity-User — **blocked by default**; per-site `evasive-allow` to permit it |
| utility | OAI-AdsBot, DuckAssistBot, Google-Read-Aloud, Google-NotebookLM |
| forged | Google-Extended, Applebot-Extended |

## Phase 3 — Per-site AI policy (ai_policy.sh)

- [ ] Opt-in training:
      `printf '<SITE> train-allow\n' > /data/disk/<OCT>/static/control/ai/policy.txt`
      → `bash /var/xdrago/ai_policy.sh` (echoes "AI policy updated … <SITE>")
      → `cat /data/disk/<OCT>/config/includes/ai_policy/<SITE>.conf` contains
      `set $ai_train_allow 1;`
- [ ] `curl -A 'GPTBot/1.1' https://<SITE>/` → now **allowed**; a *different* site still **444**.
- [ ] Opt-in evasive: change the line to `<SITE> evasive-allow` → rerun tool →
      `<SITE>.conf` contains `set $ai_evasive_allow 1;` → `curl -A 'Perplexity-User/1.0'` →
      now **allowed** (was 444); remove the line → rerun → back to **444**.
- [ ] Opt-out search: change the line to `<SITE> search-block` → rerun tool →
      `curl -A 'OAI-SearchBot/1.0'` → **444**.
- [ ] **Prune:** empty the file (or delete the line) → rerun tool (echoes "Pruned…") →
      `<SITE>.conf` gone → defaults restored (`GPTBot`→444, `OAI-SearchBot`→200).
- [ ] **Instance marker:**
      `mkdir -p /data/disk/all/static/control/ai && printf 'x.example train-allow\n' > /data/disk/all/static/control/ai/policy.txt`
      → `bash /var/xdrago/ai_policy.sh` → **no** `config/includes/ai_policy` created under
      `/data/disk/all` (it has no `tools/drush`, so it is skipped). Remove the planted file
      afterward.

## Phase 4 — Per-site IP access (ip_access.sh)

- [ ] Restrict a site to one foreign IP:
      `printf '<SITE> 198.51.100.7\n' > /data/disk/<OCT>/static/control/ip/access.txt`
      → `bash /var/xdrago/ip_access.sh`
      → `cat /data/disk/<OCT>/config/includes/ip_access/<SITE>.conf`
- [ ] **Anti-lockout present:** the fragment contains `allow 127.0.0.1;`, `allow ::1;`,
      `allow <server IP>;` (= `cat /root/.found_correct_ipv4.cnf`),
      **`allow <your SSH IP>;`** (your live session, IPv4 **or** IPv6), `allow 198.51.100.7;`,
      then `deny all;`
- [ ] From a non-allowed IP → **403**; from your SSH/server/allowed IP → **200**.
- [ ] **IPv6 + CIDR (both families):** ip_access is a pure nginx layer (no csf), so it takes
      IPv6 and subnets:
      `printf '<SITE> 198.51.100.7 203.0.113.0/24 2001:db8::1 2001:db8::/48\n' > /data/disk/<OCT>/static/control/ip/access.txt`
      → rerun → all four appear as `allow …;` lines and `configtest` passes. From an address
      inside `203.0.113.0/24` or `2001:db8::/48` (via realip, as in Phase 1) → **200**; from a
      non-listed IPv6 → **403**.
- [ ] **Bad IP/subnet is skipped, not fatal:**
      `printf '<SITE> 198.51.100.7 192.168.1.300 2001:db8::/129\n' > /data/disk/<OCT>/static/control/ip/access.txt`
      → rerun → the tool logs `Invalid IP/subnet: 192.168.1.300 … Skipping` and the same for
      `2001:db8::/129`, the fragment contains `198.51.100.7` (+ anti-lockout) but **not** the
      bad tokens, and `configtest` passes — one typo can no longer block reloads box-wide.
- [ ] **Prune:** empty the file → rerun → fragment removed → site open again.

## Phase 4b — Per-site /user + /admin IP access (user_admin_access.sh)

- [ ] Restrict just the admin surface (mix families):
      `printf '<SITE> 198.51.100.7 2001:db8::/48\n' > /data/disk/<OCT>/static/control/ip/user_admin.txt`
      → `bash /var/xdrago/user_admin_access.sh` → two fragments are written:
      `config/includes/user_admin_access_map/<SITE>.conf` (the `geo`+`map`) and
      `config/includes/user_admin_access/<SITE>.conf` (the `if ($ua_deny_*) { return 403; }`).
- [ ] **Anti-lockout present:** the `geo` always contains `127.0.0.1 1;` and `::1 1;` plus the
      server IPv4 and your live SSH peer (v4 or v6).
- [ ] From a non-allowed IP: `/admin`, `/admin/config`, `/user`, `/user/login` → **403**;
      `/` and other paths → **200**. From a listed IP (v4 single, in-CIDR, or IPv6): `/admin`
      → **200**. (BOA enforces clean URLs; the legacy `?q=admin` form is not gated here.)
- [ ] **Bad IP/subnet skipped, prune, instance-marker:** same shape as Phase 4.
- [ ] **Instance marker:** plant `access.txt` under `/data/disk/all/static/control/ip/` →
      rerun → **no** fragment generated there.

## Phase 5 — csf → nginx web bans (nginx_deny.sh)

- [ ] Web-ban a test IP: `csf -td <TESTIP> 900 -p 80` → `bash /var/xdrago/nginx_deny.sh` →
      `grep <TESTIP> /data/conf/nginx_banned_ips.conf` shows `<TESTIP> 1;`
- [ ] From `<TESTIP>` → **444**. Or simulate via realip (trust your client as in Phase 1,
      then `curl -H 'CF-Connecting-IP: <TESTIP>' https://<SITE>/` → **444**) to prove the ban
      bites on the real client IP behind CF.
- [ ] **SSH bans excluded:** `csf -td <TESTIP2> 900 -p 22` → rerun nginx_deny → `<TESTIP2>`
      is **not** in the nginx ban file.
- [ ] **Expiry:** `csf -tr <TESTIP>` (or let the 900s TTL lapse) → rerun nginx_deny →
      `<TESTIP>` drops from the file → request allowed again.
- [ ] (Optional) a `csf.deny` line tagged `Brute force Web Server` lands in the file, while
      an unrelated `csf.deny` entry does not.

## Phase 5b — nginx-native IPv6 web bans (nginx_deny6.sh)

csf is IPv4-only, so an IPv6 offender is banned at nginx instead. `scan_nginx` scores an
IPv6 realip client and writes it to `/var/xdrago/monitor/log/web6.tempban`; `nginx_deny6.sh`
mirrors it into `/data/conf/nginx_banned_ips.conf6`, read by the **same** `$is_banned` geo.

- [ ] Plant an IPv6 ban with a future expiry:
      `printf '2001:db8::66|%s\n' "$(( $(date +%s) + 900 ))" > /var/xdrago/monitor/log/web6.tempban`
      → `bash /var/xdrago/nginx_deny6.sh` →
      `grep 2001:db8::66 /data/conf/nginx_banned_ips.conf6` shows `2001:db8::66 1;`
- [ ] From `2001:db8::66` (via realip: `curl -H 'CF-Connecting-IP: 2001:db8::66' https://<SITE>/`,
      client trusted as in Phase 1) → **444**; a non-banned IPv6 → **200**.
- [ ] **Expiry:** set the entry's epoch to the past → rerun nginx_deny6 → `2001:db8::66`
      drops from `conf6` and from the store → allowed again.
- [ ] **End-to-end detection:** drive enough scored IPv6 requests (e.g. repeated `.php` 404
      probes via `CF-Connecting-IP: <a v6>`) → confirm `scan_nginx` appends it to
      `web6.tempban`, then nginx_deny6 bans it. Set `_NGINX_V6_BAN_DETECT=NO` in
      `/root/.barracuda.cnf` and confirm v6 clients are then ignored (IPv4-only behaviour).
- [ ] **clearwebbans clears v6 too:** `clearwebbans` empties `web6.tempban` and clears
      `nginx_banned_ips.conf6`.

## Phase 6 — Shared lock, rollback, idempotence

- [ ] **Lock:** launch two tools at once —
      `bash /var/xdrago/ip_access.sh & bash /var/xdrago/ai_policy.sh &` — one runs, the other
      prints "Could not acquire the shared nginx-config lock; skipping this run." (or waits
      up to 30s); no `configtest` collision. `/run/boa_nginx_config.lock` exists.
- [ ] **Rollback / safety.** Input is validated (Phase 4: a bad IP or site name is skipped,
      never emitted), so a generator won't produce invalid nginx — the revert path is a
      backstop for an *unrelated* config break. To exercise it, inject a `configtest` failure
      from outside the tool:
  1. `echo 'zzz;' >> /data/conf/nginx_banned_ips.conf` (an invalid `geo` entry).
  2. Run any generator, e.g. `bash /var/xdrago/ip_access.sh` → it reports "configtest
     failed … " and does **not** reload onto the broken config; nginx keeps serving the
     last-good config.
  3. Recover: `sed -i '/^zzz;$/d' /data/conf/nginx_banned_ips.conf && service nginx configtest && service nginx reload`.
- [ ] **Idempotence:** run any tool twice with no control change → the second run is a silent
      no-op (change-gate); no reload.

## Phase 7 — Regression spot-checks (this build)

- [ ] **netstat SSH source:**
      `netstat -tn | awk '$4 ~ /:(22|<your SSH port>)$/ && $6=="ESTABLISHED"{print $5}'` shows
      your session, and that IP appears in every generated `ip_access` fragment's allow list —
      the harvesters match the union of `22`, the cnf `_SSH_PORT` and the live sshd ports, so
      test with the port your session actually uses. (Confirms `who --ips` is gone — it is
      unavailable on Excalibur.)
- [ ] **Instance marker:** the `/data/disk/all` checks in Phases 3–4 produced no fragments
      (non-instance pseudo-dirs are skipped even when they carry a control file).
- [ ] **csf stays IPv4-only:** no IPv6 entries in `csf.allow`/`csf.deny`/`csf.tempban` —
      expected, do not "fix" (csf is the IPv4 host firewall). But IPv6 **is** handled at the
      nginx layer: `ip_access` and `user_admin_access` fragments legitimately carry IPv6/CIDR
      `allow`/`geo` entries and always emit `::1` (plus any live IPv6 SSH peer), and
      `nginx_banned_ips.conf6` carries banned IPv6 clients — those are correct, not to be removed.

## Reset the VM

- [ ] Remove test control files:
      `rm -f /data/disk/<OCT>/static/control/ai/policy.txt /data/disk/<OCT>/static/control/ip/access.txt`
      and anything planted under `/data/disk/all/...`, then rerun `ai_policy.sh` + `ip_access.sh`
      (prunes the fragments).
- [ ] Remove any manual `set_real_ip_from <CLIENTIP>;` line; clear test csf bans
      (`csf -tr <TESTIP>`).
- [ ] `service nginx configtest` → OK.
