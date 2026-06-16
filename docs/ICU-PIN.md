# Pinning ICU for PHP 7.4 `intl` (`_ICU_FORCE_VRN`)

## The problem

PHP 7.4 (and 8.0) cannot build the `intl` extension against **ICU 76+** — the build
fails. They build cleanly only against **ICU ≤ 73**. PHP 8.1+ builds `intl` against
any ICU version.

BOA installs one system-wide ICU whose version follows the OS codename
(`_resolve_icu_target` in `lib/functions/system.sh.inc`):

| tier   | variable           | version | OS codenames (default)                              |
|--------|--------------------|---------|-----------------------------------------------------|
| newer  | `_ICU_NEWER_VRN`   | `76-1`  | excalibur, daedalus, trixie, bookworm               |
| modern | `_ICU_MODERN_VRN`  | `73-1`  | chimaera, beowulf, bullseye, buster, stretch        |
| legacy | `_ICU_LEGACY_VRN`  | `52_2`  | (older / jessie)                                    |

On a "newer" OS the system ICU is 76, so a PHP 7.4 rebuilt there loses `intl`. Sites
on legacy Drupal 7 that need `intl` then break.

## The fix: pin ICU, build 7.4 with intl, unpin

`_ICU_FORCE_VRN` (set in `/root/.barracuda.cnf`) overrides the per-OS ICU version for
the whole box. The trick is to use it **transiently**:

1. Pin ICU to a 7.4-safe version (`73-1`) and run a system upgrade. ICU 73 becomes the
   active version; PHP 7.4 rebuilds **with** `intl` on ICU 73, and 8.x rebuild onto 73
   too (temporarily).
2. Remove the pin and run a system upgrade again. ICU returns to the OS default (76),
   8.x rebuild back onto ICU 76 — but **PHP 7.4 is left alone** (it is not rebuilt when
   unpinned), so it keeps its working `intl` compiled against ICU 73.

End state: **PHP 7.4 + intl on ICU 73, PHP 8.x on ICU 76** — the desired mix for boxes
hosting both legacy D7 and modern D10/D11 sites.

This works because ICU shared libraries are version-suffixed
(`libicuuc.so.73`, `libicuuc.so.76`, …) and coexist: installing ICU 76 does not remove
the ICU 73 runtime libraries that PHP 7.4's `intl` links against.

## Manual procedure (no auto-updates)

Use this on any box where BOA auto-updates are **not** enabled. Substitute your tier
verb: `up-lts` (free LTS), `up-pro` (PRO), or `up-dev`.

```bash
# 1. Pin ICU to 73 and rebuild (7.4 gains intl on ICU 73; 8.x temporarily on 73)
echo '_ICU_FORCE_VRN="73-1"' >> /root/.barracuda.cnf
barracuda up-<tier> system

# 2. Unpin and rebuild (8.x return to OS-default ICU 76; 7.4 keeps its ICU-73 intl)
sed -i '/^_ICU_FORCE_VRN=/d' /root/.barracuda.cnf
barracuda up-<tier> system
```

### Verify

```bash
readlink /usr/local/lib/icu/current            # -> /usr/local/lib/icu/76.1 (after unpin)
/opt/php74/bin/php -m | grep -i intl           # -> intl
/opt/php74/bin/php -i | grep -i 'ICU version'  # -> ICU version => 73.1
ldd /opt/php74/bin/php | grep -i icu           # -> libicu*.so.73 all resolve (no "not found")
/opt/php83/bin/php -i | grep -i 'ICU version'  # -> ICU version => 76.1
```

## Automatic handling (auto-updates enabled)

Where BOA auto-updates are configured, the weekly system-upgrade cron is routed
through a wrapper in `autoupboa` instead of calling `barracuda` directly:

```
* * * <weekly>  root  bash /opt/local/bin/autoupboa weekly-system up-<tier> system [php-*] noscreen
```

On each weekly run `autoupboa weekly-system` checks for the regression and, only if
PHP 7.4 is installed **without** `intl`, performs the pin → rebuild → unpin → rebuild
cycle automatically (idling inactive PHP versions first to limit the rebuild surface);
otherwise it runs the normal system upgrade. Once 7.4 carries `intl`, detection is
false and the plain upgrade path runs — so it is self-limiting.

Notes:

- This applies on **every branch** (dev/pro/lts) — the tier is irrelevant. It runs
  wherever the weekly upgrade cron is written, i.e. boxes that have auto-updates
  configured and are **not** flagged as development/scratch servers (`/root/.dev.server.cnf`,
  which is independent of the BOA branch). Boxes outside that set use the manual
  procedure above.
- The orchestration lives in `autoupboa`, never in `barracuda` itself — `barracuda` is
  only ever invoked as a leaf process, so it cannot self-call and loop.
- A resume marker (`/var/log/boa/.php74_intl_bootstrap.active`) ensures an interrupted
  run cannot leave a box stuck pinned.
- Deploying this behaviour to existing boxes requires the `autoupboa` fetch serial and
  the hardcoded `ctrl_595vNN` crontab-update marker to be bumped together, so boxes
  regenerate `/etc/crontab` once and pick up the new weekly line.

## Caveats

- **Durability.** PHP 7.4 keeps `intl` only as long as it is **not rebuilt while
  unpinned**. The build only adds `--enable-intl` for 7.4 when `_ICU_FORCE_VRN` is set
  (`lib/functions/php.sh.inc`), so a forced 7.4 rebuild with the pin off (e.g. an
  OpenSSL change, `php-max`/`php-min`, a version bump) would drop `intl`. PHP 7.4 is
  EOL, so this is rare — but **re-pin before deliberately rebuilding 7.4**. A 7.4 that
  is simply left untouched survives ICU upgrades.
- **Cost.** The pin pass rebuilds all active PHP versions onto ICU 73; the unpin pass
  rebuilds 8.x back onto ICU 76 — so 8.x compile twice. This is a one-time transition
  cost, but it is real per-rebuild downtime.
- **ICU 73 runtime libraries must remain.** PHP 7.4's `intl` links against
  `/usr/local/lib/libicu{i18n,uc,data}.so.73*`. They persist across an ICU 76 install
  (versioned sonames coexist), but a manual purge of old ICU libraries would break 7.4
  `intl`.

## Retirement

To return a box fully to the OS-default ICU, just remove the pin and upgrade
(`sed -i '/^_ICU_FORCE_VRN=/d' /root/.barracuda.cnf; barracuda up-<tier> system`). ICU
and 8.x return to the default; 7.4 keeps its frozen ICU-73 `intl` until it is next
rebuilt (see Durability).
