# Restricting a site to specific IP addresses

You can lock an individual site down so that only certain IP addresses can reach it —
useful for an intranet, a staging site, or an admin-only area. Everyone else gets a
"403 Forbidden".

## How to do it

In the Octopus instance that hosts the site, edit (create if missing) the file:

```
static/control/ip/access.txt
```

On a typical box that is `/data/disk/<instance>/static/control/ip/access.txt`, where
`<instance>` is the Octopus user (e.g. `o1`) that hosts the site — your administrator can
tell you which one. Add one line per site: the site name, then the IP addresses allowed
to reach it.

```
# static/control/ip/access.txt

intranet.example.com   203.0.113.10 203.0.113.11
staging.example.com    198.51.100.42
```

Use the visitor's **real public IP** (what `https://ifconfig.co` or similar shows for
them) — not a local/LAN address. `#` comments and blank lines are ignored.

## You cannot lock yourself (or the server) out

Three things are always allowed in addition to your list, so a typo can't strand the
site: the server's own address, the loopback, and any address currently logged in over
SSH. You never need to add those yourself.

## When it takes effect

Changes are picked up automatically within about **two minutes**. To open a site back up
to everyone, delete its line — the restriction is removed on the next pass.

## Good to know

- Addresses are individual IPv4 addresses, listed with spaces between them — not ranges.
- The restriction covers the whole site.
- If your sites sit behind Cloudflare, the list still works on the visitor's real IP (the
  platform recovers it), so enter the real client address as usual.
