# Testing the AI policy, realip, per-site control and bans (disposable VM)

End-to-end verification checklist for the whole edge-policy stack: AI bot classification,
Cloudflare realip, per-site AI policy, per-site IP access, and the csf→nginx web-ban
mirror. Intended for a throwaway VM where you can ban yourself and break things freely.
Mechanics are documented in [AI-POLICY.md](AI-POLICY.md) and [IP-ACCESS.md](IP-ACCESS.md);
this is the runbook to confirm they behave on a real box.

## Conventions

Run each generator **manually** after editing a control file — it executes immediately and
echoes what it did, which is deterministic, instead of waiting for the `*/2` cron:

```bash
bash /var/xdrago/ip_access.sh
bash /var/xdrago/ai_policy.sh
bash /var/xdrago/nginx_deny.sh
bash /var/xdrago/cloudflare_realip.sh
```

Placeholders: `<SITE>` = a real vhost on the box, `<OCT>` = its Octopus instance (e.g.
`o1`), `<TESTIP>` = a throwaway IP, `<CLIENTIP>` = the address your test machine reaches
the VM from.

Two things to keep straight so you don't read a false negative:

- **Rate-limit throttling returns `503`** (the `limit_req` default); the hard guards
  (training/forged/secret-path/banned) return **`444`**. Don't confuse them.
- **realip only rewrites `$remote_addr` when the request's peer is inside a
  `set_real_ip_from` range.** A direct hit from your laptop is not a CF edge, so the CF
  tests below first add `<CLIENTIP>` to the trusted set.

## Phase 0 — Deploy and presence

- [ ] Run the upgrade that ships this code (`barracuda up-<tier> system`); finishes clean.
- [ ] All four tools present: `ls -l /var/xdrago/{ip_access,ai_policy,nginx_deny,cloudflare_realip}.sh`
- [ ] Crontab has them (first three `*/2`, cloudflare_realip daily):
      `crontab -l | grep -E 'ip_access|ai_policy|nginx_deny|cloudflare_realip'`
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

- [ ] `GPTBot/1.1` (training) → **444**
- [ ] `OAI-SearchBot/1.0` (search) → **200**
- [ ] `ChatGPT-User/1.0` (user) → **200**
- [ ] `OAI-AdsBot/1.0` (utility) → **200**
- [ ] `Google-Extended` (forged opt-out token as a UA) → **444**
- [ ] `Mozilla/5.0 (...)` (normal browser) → **200**
- [ ] Secret-path probe → **444**: `curl -s -o /dev/null -w '%{http_code}\n' https://<SITE>/.env`
      (also `/.git/config`, `/config.json`)
- [ ] **Rate-limit** (throttle = **503**, not 444):
      `for i in $(seq 20); do curl -s -o /dev/null -w '%{http_code} ' -A 'OAI-SearchBot/1.0' https://<SITE>/; done; echo`
      → first few `200`, then `503` (search zone = 1 r/s). Repeat with `Mozilla/...` → all
      `200` (browsers are never charged to an AI zone).

Tokens per class (any one matches the class):

| Class | Tokens |
|-------|--------|
| training | GPTBot, ClaudeBot, Claude-Web, anthropic-ai, CCBot, Bytespider, Amazonbot, AI2Bot, Diffbot, Meta-ExternalAgent, cohere-ai, omgili |
| search | OAI-SearchBot, Claude-SearchBot, PerplexityBot, MistralAI-Index, YouBot, Google-CloudVertexBot |
| user | ChatGPT-User, Claude-User, Perplexity-User, MistralAI-User, Meta-ExternalFetcher |
| utility | OAI-AdsBot, DuckAssistBot, Google-Read-Aloud, Google-NotebookLM |
| forged | Google-Extended, Applebot-Extended |

## Phase 3 — Per-site AI policy (ai_policy.sh)

- [ ] Opt-in training:
      `printf '<SITE> train-allow\n' > /data/disk/<OCT>/static/control/ai/policy.txt`
      → `bash /var/xdrago/ai_policy.sh` (echoes "AI policy updated … <SITE>")
      → `cat /data/disk/<OCT>/config/includes/ai_policy/<SITE>.conf` contains
      `set $ai_train_allow 1;`
- [ ] `curl -A 'GPTBot/1.1' https://<SITE>/` → now **200**; a *different* site still **444**.
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
- [ ] **Anti-lockout present:** the fragment contains `allow 127.0.0.1;`,
      `allow <server IP>;` (= `cat /root/.found_correct_ipv4.cnf`),
      **`allow <your SSH IP>;`** (your live session), `allow 198.51.100.7;`, then `deny all;`
- [ ] From a non-allowed IP → **403**; from your SSH/server/allowed IP → **200**.
- [ ] **Bad IP is skipped, not fatal:**
      `printf '<SITE> 198.51.100.7 192.168.1.300\n' > /data/disk/<OCT>/static/control/ip/access.txt`
      → rerun → the tool logs `Invalid IP: 192.168.1.300 … Skipping`, the fragment contains
      `198.51.100.7` (+ anti-lockout) but **not** `192.168.1.300`, and `configtest` passes —
      one typo'd octet can no longer block reloads box-wide.
- [ ] **Prune:** empty the file → rerun → fragment removed → site open again.
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
      `netstat -tn | awk '$4 ~ /:22$/ && $6=="ESTABLISHED"{print $5}'` shows your session, and
      that IP appears in every generated `ip_access` fragment's allow list. (Confirms
      `who --ips` is gone — it is unavailable on Excalibur.)
- [ ] **Instance marker:** the `/data/disk/all` checks in Phases 3–4 produced no fragments
      (non-instance pseudo-dirs are skipped even when they carry a control file).
- [ ] **IPv6 by policy:** no IPv6 entries in csf or in any fragment — expected, do not "fix".

## Reset the VM

- [ ] Remove test control files:
      `rm -f /data/disk/<OCT>/static/control/ai/policy.txt /data/disk/<OCT>/static/control/ip/access.txt`
      and anything planted under `/data/disk/all/...`, then rerun `ai_policy.sh` + `ip_access.sh`
      (prunes the fragments).
- [ ] Remove any manual `set_real_ip_from <CLIENTIP>;` line; clear test csf bans
      (`csf -tr <TESTIP>`).
- [ ] `service nginx configtest` → OK.
