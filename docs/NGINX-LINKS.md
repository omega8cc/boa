# The nginx link check (`_NGINX_LINK_GUARD`)

## The problem it solves

Nginx follows symbolic links by default. Every account on a BOA system can
write into its own sites, so it can also put a link there that leads to
another account's files, and Nginx serves whatever the link leads to as if it
were the site's own file.

Nginx can refuse that: with `disable_symlinks if_not_owner;` it refuses any
path where a component is a link whose owner is not the owner of what the
link leads to. A link an account makes is owned by that account, and another
account's files are not, so such a path is refused.

## Why BOA's own links come first

BOA itself uses links in the sites it serves, and some of them have owners
that differ from their targets:

- the Drupal 6 and 7 platforms link their core files and directories
  (`index.php`, `misc`, `modules`, `includes` and the rest, and `profiles`) to
  the shared core in `/data/all`;
- every platform links the shared contrib bundles (`modules/o_contrib*`) and,
  on Drupal 6 and 7, `js.php`;
- the account's control panel links `modules/o_contrib_seven/redis_edge`.

The account's own tools make these links, so the account owns them, while
the shared code they lead to is root's. With the check on and these links
unchanged, every Drupal 6 and 7 site on the system would stop working.

linkguard makes them pass. A link at one of these places that leads into
root's shared code is made again by root, with the same target, under a new
name, and renamed over the old one. It is made root's only when every
directory on its way, and what it leads to, is root's and writable by root
alone, inside the shared store (`/data/all`, or `/data/disk/all` where
`/data/all` is root's link to it), so such a link can lead nowhere but
shared code.

A link inside one account whose owner differs from its target's (the files
link of a site whose owner has changed, a link root made into the account's
own store) is made again by the owner of what it leads to, the same way.

## When it switches itself on

`_NGINX_LINK_GUARD=YES` in `/root/.barracuda.cnf` arms the system: every
barracuda pass then writes the arm stamp `/var/log/boa/linkguard-arm.ready.txt`
and runs `linkguard apply`, which

1. makes BOA's links pass on every platform BOA builds and in every root
   Nginx serves;
2. scans every root and alias Nginx serves (from `nginx -T`), the directories
   above them, and the directories their links lead to;
3. writes `/etc/nginx/conf.d/link-guard-boa.conf` with the one directive,
   tests the configuration and reloads Nginx, but only when the scan finds
   no link the check would break.

Once on, the check stays on whatever a later scan finds: a link an account
plants must never switch it off. `_NGINX_LINK_GUARD=NO` switches it off at
the next barracuda pass. `linkguard off` switches it off at once and disarms
the system until the next barracuda pass; while `_NGINX_LINK_GUARD=YES` is
still set that pass arms it again, so set `NO` to keep it off.

Every platform Verify makes that platform's links pass as well (the platform
ownership script runs `linkguard fix --root=<platform>` each time it ends),
so a platform built after the check was switched on stops serving through a
link the check refuses when its Verify ends. The nightly maintenance (owl.sh)
runs `linkguard apply` once a night, so a system switches itself on the night
its scan comes out clean.

A link inside an account can start to be refused in between: when BOA hands
the files it leads to over to the account's backend user (the nightly's and
a site Verify's hand-over of uploaded code), the link keeps the owner it was
made with. It is made its target owner's by the next Verify of its platform
or by that night's pass.

Not switched on in this release: the setting arms only a test system that
carries the marker `/root/.tenant-isolation-test.cnf`. A later release lets
it arm every system.

## What the scan reports

The scan writes `/var/log/boa/linkguard.report.txt`, one line per link whose
owner differs from its target's:

- `BLOCKING` keeps the check off: a link root made, a link of a system user
  or of a user that no longer exists, a BOA link that could not be made
  root's, or a link inside one account that could not be made its target
  owner's. Turning the check on would break each of these.
- `REFUSED` never keeps it off: a link an account made that leads out of
  that account. That is exactly what the check is there to refuse.
- `NOTE` names a configuration file that sets `disable_symlinks` itself; a
  server or location that sets it overrides the box-wide setting there.

The check also stays off while a scan could not finish: the report's third
line then says `complete=0`, and `apply` says `reason=incomplete`.

The nightly mails the operator once a day while anything blocking or refused
is listed (unless `_INCIDENT_REPORT=OFF`), and logs it in
`/var/log/boa/nightly.incident.log`.

## Verify, and find out why it is off

```
linkguard status    # armed or not, on or off, the last scan's summary
linkguard scan      # scan again now (read-only), the report rewritten
grep -c '^BLOCKING' /var/log/boa/linkguard.report.txt
```

A system stays off while the report lists anything `BLOCKING`. Remove or
replace each such link, or make its owner match its target's, and the next
barracuda pass or night switches the check on.

## What it does not change

- PHP follows links on its own; the check covers what Nginx itself serves
  and the existence tests in the vhosts (`try_files`, `if -e`), not files
  PHP reads. Tenant PHP isolation rests on the per-account web group
  (docs/INSTGRP.md).
- A refused path answers as a missing file does wherever the vhost tests it
  first (`try_files`, `if -e`), which is how BOA's vhosts serve most static
  files: 404, or the next `try_files` choice. Served without such a test, it
  answers 403. Nginx keeps a refusal in its open file cache for up to 99
  seconds per worker; linkguard reloads Nginx whenever it makes a link pass
  while the check is on, which clears it.
- Links Nginx reads its configuration through, certificates and include
  files are not checked.
