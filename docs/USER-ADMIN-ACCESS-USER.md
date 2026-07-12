# Restricting login and admin to specific IP addresses

You can lock down just the **login and admin area** of a site — the `/user` and `/admin`
pages — so that only certain addresses can reach them, while the rest of the site stays
open to everyone. Anyone else who tries to open `/user` or `/admin` gets a "403
Forbidden". This is ideal when you want the public site available to all visitors but the
admin/login surface reachable only from your office, VPN, or home connection.

## How to do it

In the Octopus instance that hosts the site, edit (create if missing) the file:

```
static/control/ip/user_admin.txt
```

On a typical box that is `/data/disk/<instance>/static/control/ip/user_admin.txt`, where
`<instance>` is the Octopus user (e.g. `o1`) that hosts the site — your administrator can
tell you which one. Add one line per site: the site name, then the addresses allowed to
reach `/user` and `/admin`.

```
# static/control/ip/user_admin.txt

intranet.example.com   203.0.113.10 203.0.113.0/24 2001:db8::/32
staging.example.com    198.51.100.42 2001:db8:1::1
```

You can list **IPv4 or IPv6** addresses, and either single addresses or whole ranges in
CIDR notation (`203.0.113.0/24`, `2001:db8::/32`, …). Use the visitor's **real public
address** (what `https://ifconfig.co` or similar shows for them) — not a local/LAN
address. `#` comments and blank lines are ignored.

## You cannot lock yourself (or the server) out

Some addresses are always allowed in addition to your list, so a typo can't strand you out
of the admin area: the server's own address, the loopback, and any address currently
logged in over SSH. You never need to add those yourself.

## When it takes effect

Changes are picked up automatically within about **two minutes**. To open `/user` and
`/admin` back up to everyone, delete the site's line — the restriction is removed on the
next pass.

## Good to know

- This restricts only `/user` and `/admin` (and pages under them). The rest of the site
  stays public. To lock down a **whole** site instead, see the separate whole-site IP
  access feature.
- Addresses are listed with spaces between them; each can be a single IPv4/IPv6 address or
  a CIDR range.
- It is an extra gate at the web-server edge — your normal Drupal login still applies on
  top of it.
- If your sites sit behind Cloudflare, the list still works on the visitor's real address
  (the platform recovers it), so enter the real client address as usual.
