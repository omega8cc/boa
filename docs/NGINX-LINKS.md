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

A link at one of these places whose text has another form (a relative one,
one with `..` in it) but still ends inside the shared store is written in
the plain form, `/data/all/...`, when root makes it again.

A link inside one account whose owner differs from its target's (the files
link of a site whose owner has changed, a link root made into the account's
own store, a link one of the account's logins made to a file of its backend
user) is made again by the owner of what it leads to, the same way. That
works in a directory this owner cannot write as well, such as one a login
keeps for itself: the link is still made by its owner, never handed over by
name.

## When it switches itself on

`_NGINX_LINK_GUARD=YES` in `/root/.barracuda.cnf` arms the system: every
barracuda pass then writes the arm stamp `/etc/boa/control/linkguard-arm.ready.txt`
(an earlier release wrote it in `/var/log/boa`; a pass that disarms and `linkguard
off` remove that one too) and runs `linkguard apply`, which

1. makes BOA's links pass on every platform BOA builds and in every root
   Nginx serves;
2. scans every root and alias Nginx serves (from `nginx -T`), the directories
   above them, and the directories their links lead to;
3. writes `/etc/nginx/conf.d/link-guard-boa.conf` with the one directive,
   tests the configuration and reloads Nginx, but only when the scan finds
   nothing `BLOCKING` (see below).

A link inside an account's own tree never keeps the check off, so no
account can hold a system back by leaving one in place: linkguard makes it
its target owner's where it can, and a link it cannot make so is refused
for that account only once the check is on, and reported.

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

When BOA hands files over to the account's backend user (the nightly's and
a Verify's hand-over of uploaded code), a link to them keeps the owner it
was made with. The same run makes it its target owner's: a site Verify runs
`linkguard fix --tree=<site>` when it ends, and once a day, right after it
has handed the site's files and private stores over, the same for each
store.

During the nightly the stores are left to the night's own pass, which
covers every one of them when it ends; a link inside a store whose target
the night handed over is refused until then.

Not switched on in this release: the setting arms only a test system that
carries the marker `/root/.tenant-isolation-test.cnf`. The release that
switches it on also writes `_NGINX_LINK_GUARD=YES` into a
`/root/.barracuda.cnf` that has no such line, on the hosted systems first
and on every system in a later release, both after the account web group's
(docs/INSTGRP.md). A `NO` set there keeps a system out.

## What the scan reports

The scan writes `/var/log/boa/linkguard.report.txt`, one line per link whose
owner differs from its target's:

- `BLOCKING` keeps the check off: a link root made (outside an account's
  tree, leading out of the account it is in, or to a file in that account's
  tree none of the account's identities owns), a link of a system user or
  of a user that no longer exists, or a BOA link at one of the places BOA
  itself makes them that could not be made root's (something on its way
  into the shared store is not root's alone). Turning the check on would
  break each of these; a link inside one account is never among them.
- `REFUSED` never keeps it off: a link inside one account that is not its
  target owner's and could not be made so, or a link an account made that
  leads out of that account, which is exactly what the check is there to
  refuse. Either is refused once the check is on, for that account only.
  A link leading out says where it leads: into the shared store, or into
  another account's tree or to its files (a share between two accounts).
- `NOTE` names a configuration file that sets `disable_symlinks` itself; a
  server or location that sets it overrides the box-wide setting there.

The check also stays off while a scan could not finish: the report's third
line then says `complete=0`, and `apply` says `reason=incomplete`. Directories
reached only through an account's own links never cause that: past the walk's
bound they are left out and counted in a `NOTE` line.

An account's tree is `/data/disk/<account>`, its files store on attached
storage (`/mnt/<mount>/files/<account>/static/files`) and the home of each of
its logins. Root's own links in a login's home (`static`, `backups`,
`clients`) are left as they are; reached through a link the account made to
that home they are refused, and never keep the check off.

The nightly mails the operator once a day while anything blocking or refused
is listed (unless `_INCIDENT_REPORT=OFF`), and logs it in
`/var/log/boa/nightly.incident.log`.

## The nightly count

Every night, on every system whether it is armed or not, the nightly
maintenance starts `linkguard count` once its account steps are done, and
does not wait for it. It walks what Nginx serves the way the scan does, at
the lowest CPU and disk priority, and appends one dated line to
`/var/log/boa/linkguard/count.log`. It changes nothing: no link is fixed,
the check is not switched, no mail is sent, the scan's report is left as it
is, and Nginx is only asked for its configuration (`nginx -T`).

A count stops after an hour; its line then says `result=deadline
complete=0`. Only one count runs at a time, and it holds up no other
linkguard run; a count that waited a minute for another one says
`result=busy`.

A line counts the links whose owner differs from their target's, by kind.
Where the target is decides between `root-in` and `root-out`, and between
`in-other` and `out`; where the link is decides `system-in`; who owns the
target decides `inside`:

| key | class | the link |
|---|---|---|
| `root-out` | BLOCKING | root's, in an account's tree, to a file outside that tree |
| `system-in` | BLOCKING | a system user's or an unknown user's, in an account's tree |
| `share` | REFUSED | an account's, into another account's tree or to its files |
| `store` | REFUSED | an account's, into the shared store at a place BOA does not link |
| `root-in` | BLOCKING | root's, in an account's tree, to a file there none of its identities owns |
| `root` | BLOCKING | root's, outside any account's tree |
| `system` | BLOCKING | a system user's or an unknown user's, outside any account's tree |
| `boa` | BLOCKING | a BOA link at a BOA place that `linkguard fix` cannot make root's |
| `boa-fix` | | a BOA link at a BOA place that is not root's yet, and that `apply` makes root's before it switches the check on |
| `inside` | REFUSED | inside one account, not its target owner's (`fix` makes it so where it can) |
| `in-other` | REFUSED | an account's, to a file in its own tree none of its identities owns |
| `out` | REFUSED | an account's, leading anywhere else out of it |

On a system never armed nothing has made BOA's own links root's, so most of
them show up as `boa-fix`. After the kinds come the totals: `blocking`, the
links that would still keep the check off once `apply` has made BOA's links
root's (`boa-fix` is not in it), and `refused`; then whether the walk
finished (`complete`), what it walked (`roots`, `missing`, `entries`,
`unwalked`) and how long it took (`secs`). `state` and `armed` say whether
the check was on and the system armed; on an armed system the count runs
after the night's `apply`, so it counts what that left. A night that could
not count says why instead (`result=busy`, `result=no-nginx-config`,
`result=no-scan`).

```
tail -n 7 /var/log/boa/linkguard/count.log   # the last week
linkguard status                             # ends with the last count
```

The log lives in a directory of its own, which the clean-up of
`/var/log/boa/*.log` during a major system upgrade leaves alone, and is
kept.

## Verify, and find out why it is off

```
linkguard status    # armed or not, on or off, the last scan's summary
linkguard scan      # scan again now (read-only), the report rewritten
grep -c '^BLOCKING' /var/log/boa/linkguard.report.txt
```

A system stays off while the report lists anything `BLOCKING`. Remove or
replace each such link, or make its owner match its target's, and the next
barracuda pass or night switches the check on. It also stays off, with
`reason=no-heal`, when a link inside an account could not be made and a test
then shows that `setpriv` cannot make a link as another user on this system
at all: every such link would be refused.

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
