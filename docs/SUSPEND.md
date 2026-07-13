# Suspending an Octopus Instance

`boa suspend <user>` turns off web serving for one Octopus instance — every
site hosted under the account answers **503 Service Unavailable** with a neutral
"temporarily unavailable" page — and `boa unsuspend <user>` restores it. The
intended use is billing enforcement (a hosted client with an overdue invoice),
but nothing about the mechanism is billing-specific.

Both commands are instant and idempotent: suspending an already-suspended
instance (or unsuspending a non-suspended one) just reports the current state.
Other instances on the same box are not affected.

## What suspend does — and what it deliberately does not

When suspended:

- **Web requests get a 503** on every site of the account, Drupal and Backdrop
  alike. The response carries `Retry-After: 3600` and `Cache-Control: no-store`,
  so nothing downstream caches the outage page, and the Nginx speed cache is
  purged at both toggle points — the 503 appears immediately on suspend and
  clears immediately on unsuspend.
- **Nothing else changes.** No files, databases, vhosts or certificates are
  touched. SSH/SFTP access for the account users keeps working. Backend
  contexts — drush, Ægir tasks, cron — stay fully functional, so the Ægir
  frontend keeps managing the account's sites while it is suspended.

Suspend is completely separate from the two mechanisms it superficially
resembles:

- `log/CANCELLED` marks an instance for **cleanup/purge** (see
  [CLEANUP.md](CLEANUP.md)) and arms vhost removal on the next `barracuda up-*`.
  A suspended instance never enters that machinery.
- `static/control/http-off.pid` is the **migration** web-off gate managed by
  `xoct`/`xmass` (see [MIGRATE-XOCT.md](MIGRATE-XOCT.md)). It lives inside the
  account tree and serves a cacheable maintenance page.

## Mechanism

`boa suspend <user>` drops a flag at `/data/conf/suspended/<user>.pid`
(contents: the suspension epoch, useful as an operator breadcrumb). The global
settings include, which every hosted site loads before bootstrap, answers all
web requests on a flagged account with the 503 short-circuit; backend and CLI
contexts are exempt.

The flag lives **outside the account tree on purpose**: `/data/conf` is
root-owned, so the account owner cannot remove the flag through shell or SFTP
access. `boa unsuspend <user>` removes the flag and purges the speed cache.

## Usage

```
boa suspend o3
boa unsuspend o3
```

An unknown or nonexistent instance is refused with a nonzero exit code.
