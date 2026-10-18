# Sites on an unsupported Drupal core minor (eolreport)

`eolreport` lists the Drupal 8+ sites on a server whose platform runs a core minor that drupal.org no longer supports. Such a site cannot take a security release in place: it needs a platform on a supported minor and a Migrate. The tool reads; it changes nothing.

## Where the list comes from

The server never asks drupal.org. The catalogue build on the mirror (`staticbuild`) reads `supported_branches` from drupal.org's release history when it builds the vanilla cores and publishes it as `core/drupal-supported.txt` beside the core tarballs. Every server takes that file with its daily tools refresh (`BOA.sh.txt`, `_fetch_core_coverage`) from the mirror it already talks to and keeps the last good copy at `/var/log/boa/drupal-supported.txt`; a fetch that fails, or that returns anything but one line of minors, leaves that copy alone. A mirror box reads its own tree.

A minor outside the list gets no routine security fix. drupal.org sometimes adds a best-effort fix for an older minor when a flaw is highly critical; that does not put the minor back on the list.

## Usage

```
eolreport          # the sites outside the supported minors
eolreport --all    # every Drupal 8+ site, with its core version and its standing
```

Each line: the Octopus account, the site, the platform's core version, `ok` or `OUTSIDE`, the site's root. The first line names the list and the date of the server's copy. Exit code 0 when no site is outside, 1 when one or more are, 2 when the server has no list yet (it arrives with the daily tools refresh).

## What is read

A site is read from its Drush alias under `/data/disk/oN/.drush/`; the platform's core version from `core/lib/Drupal.php` under the site's root. Drupal 6 and 7 (BOA's own long-term cores), Backdrop, Grav and Textpattern sites have no such file and are left out.
