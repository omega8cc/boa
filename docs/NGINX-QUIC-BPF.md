# HTTP/3 across Nginx reloads (`_NGINX_QUIC_BPF`)

## The problem it solves

When Nginx reloads its configuration, the new worker processes inherit the
listening sockets of the old ones. For TCP that is harmless: a connection in
progress stays with its old worker until it finishes. For QUIC it is not. The
UDP sockets are shared, packets of an HTTP/3 connection in progress reach a
new worker that holds no state for it, and the transfer is reset within
seconds of the reload.

A BOA system reloads Nginx routinely — after Ægir tasks and whenever a ban
list changes — often every few minutes. A page load fits between two reloads
and never notices; a long transfer over HTTP/3 (a large download, a media
stream) does not.

Nginx answers this with `quic_bpf on;`: an eBPF program routes every QUIC
packet to the worker that owns its connection, so the old workers drain their
HTTP/3 connections just as they drain TCP ones.

## Why it is probed instead of simply switched on

The eBPF program is loaded only on a real start. `nginx -t` does not load it,
so a configuration test passes even on a system where the load would fail (a
container without the capability, an old kernel, a tight limit) — and on such
a system a start with `quic_bpf on;` makes Nginx refuse to start at all.

So on every barracuda pass, a fresh install included, after the last Nginx
restart of that pass, BOA first starts a throwaway Nginx master — the same
binary, user and worker count, one QUIC listener on a loopback port — and
writes the directive only when that master started and logged no complaint.
The probe normally takes about half a second, gives up within a few seconds
at most, stops its master by its own pid and removes its files. A probe that
fails is tried once more before the verdict counts. The directive also needs
Linux 5.7 or newer and an Nginx built with the HTTP/3 module; where the probe
fails or either is missing, nothing is written and a fragment written earlier
is removed on that pass.

The directive lives in its own fragment, `/etc/nginx/main.d/quic_bpf.conf`.
Every pass makes sure `/etc/nginx/main.d/` exists and that
`/etc/nginx/nginx.conf` includes `main.d/*.conf` from its main context: a
`nginx.conf` older than the template that carries the line gets it inserted
after its `pid` line, tested with `nginx -t` and put back as it was if the
test fails. This happens whatever the setting below says — the setting
governs the fragment, not the include.

The fragment is switched with a reload (made only when `nginx -t` passes),
never with a restart of its own. A reload cannot take Nginx down — a failed
eBPF load is only logged there — but it is also the first load that sees the
system's real listeners and the running master's limits, so BOA reads the
error log right after the enabling reload: a failure there removes the
fragment again and leaves the latch described below. What remains is the
first real start with the fragment in place (a reboot, a service restart),
and that is what the safety net is for.

## The safety net

If Nginx ever fails to start with the fragment in place — something changed
after the probe passed — the Nginx monitor removes the fragment, starts Nginx
again, records the incident in `/var/log/boa/nginx.incident.log` and leaves a
latch:

```
/etc/nginx/main.d/quic_bpf.failed
```

The monitor mails the incident only when `_INCIDENT_REPORT=ALL` (see
[MONITOR.md](MONITOR.md)); otherwise the incident log line and the latch are
the signal. It acts on evidence: a BPF failure in the error log it rotated
just before that start, or a binary that no longer knows the directive.
Failing both, and at most once in ten minutes, it starts Nginx without the
fragment and keeps it shed only if that is what made the difference; a start
that fails for some other reason (a busy port, a broken vhost) gets its
fragment back and is left to the usual handling.

While the latch exists no pass writes the fragment again, whatever
`_NGINX_QUIC_BPF` says. The file itself says when and why it was left. Delete
it once the cause is understood and the next pass probes afresh.

## The lever

`_NGINX_QUIC_BPF` in `/root/.barracuda.cnf`:

- **`YES` (default)** — the probe runs on every pass and the fragment follows
  its verdict.
- **`NO`** — the fragment is removed on the next `barracuda up-*` and not
  written again.

Substitute your tier verb: `up-lts` (free LTS), `up-pro` (PRO), or `up-dev`.

```bash
sed -i '/^_NGINX_QUIC_BPF=/d' /root/.barracuda.cnf
echo '_NGINX_QUIC_BPF=NO' >> /root/.barracuda.cnf
barracuda up-<tier> system
```

Re-enable by removing the line and, if the monitor left one, the latch:

```bash
sed -i '/^_NGINX_QUIC_BPF=/d' /root/.barracuda.cnf
rm -f /etc/nginx/main.d/quic_bpf.failed
barracuda up-<tier> system
```

To shed it at once, without waiting for a pass (set the variable as well, or
the next pass writes it back):

```bash
rm -f /etc/nginx/main.d/quic_bpf.conf
service nginx reload
```

## Verify, and find out why it is off

```bash
# The directive is configured when this prints it.
nginx -T 2>/dev/null | grep '^quic_bpf'

# No line here since the last start or reload means the eBPF load succeeded.
grep -E 'ngx_quic_bpf_module failed|failed to create BPF' /var/log/nginx/error.log

# Present only after a load or a start that failed with the directive on.
cat /etc/nginx/main.d/quic_bpf.failed
```

A pass that leaves it off says why in its output, in one line beginning
`INFO: quic_bpf stays off:` — the latch, a `nginx.conf` without the `main.d`
include, the kernel, an Nginx without HTTP/3, or a probe that failed — and
stays silent only for `_NGINX_QUIC_BPF=NO`. The pass that removes a fragment
says `INFO: quic_bpf disabled:` with the same reasons, the one that writes it
says so too, and an `ALERT:` line reports a `nginx -t` that rejected the
include line or the fragment, or an eBPF load that failed on the enabling
reload. The same facts by hand:

```bash
grep '^_NGINX_QUIC_BPF' /root/.barracuda.cnf
uname -r
nginx -V 2>&1 | grep -o 'with-http_v3_module'
```

## What it does not change

The Ægir control panel does not offer HTTP/3 at all: its per-instance HTTPS
front carries no QUIC listener and answers `Alt-Svc: clear`. Hosted sites keep
HTTP/3, and this setting is what keeps their HTTP/3 transfers alive across
reloads.
