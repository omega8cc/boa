# PHP `intl` and the system ICU (`_ICU_FORCE_VRN`)

## How BOA builds `intl`

BOA installs one system-wide ICU whose version follows the OS codename
(`_resolve_icu_target` in `lib/functions/system.sh.inc`):

| tier   | variable           | version | OS codenames (default)                              |
|--------|--------------------|---------|-----------------------------------------------------|
| newer  | `_ICU_NEWER_VRN`   | `76-1`  | excalibur, daedalus, trixie, bookworm               |
| modern | `_ICU_MODERN_VRN`  | `73-1`  | chimaera, beowulf, bullseye, buster, stretch        |
| legacy | `_ICU_LEGACY_VRN`  | `52_2`  | (older / jessie)                                    |

Every PHP 7.4 and newer is built with the `intl` extension against that ICU:

- PHP 8.1 and newer build `intl` against any ICU version.
- PHP 7.4 and 8.0 compile `intl` as C++11, while the headers of ICU 75 and newer
  need C++17. On such an ICU, barracuda raises the C++ standard for the `intl`
  sources of these two versions (`ICU_CXXFLAGS=-std=c++17`), the same change PHP 8.1
  made upstream for these ICU versions. Nothing else in the build changes.
- PHP 7.3 and older are built without `intl`: the 7.2/7.3 `intl` sources do not
  compile against ICU 70 or newer, and 5.6 to 7.1 never had `intl` in BOA.

So on Daedalus and Excalibur, PHP 7.4, 8.0 and every 8.x carry `intl` on the same
ICU 76, with no pin and no operator step.

## It stays that way

Every barracuda pass that checks the installed PHP versions compares the ICU each
7.4+ build was compiled against (`php -i`, `ICU version`) with the ICU this box
expects. A version built without `intl`, or against another ICU, is rebuilt in the
same pass. That holds on every route that can rebuild PHP: a plain
`barracuda up-<tier> system`, `php-max` and `php-min` runs, a rebuild forced by an
OpenSSL update or a new PHP release, and the weekly auto-update run.

Prebuilt PHP packages (see [PREBUILT.md](PREBUILT.md)) are checked the same way: a
7.4 or 8.0 package built without `intl`, or against another ICU, is refused and
purged, and that version builds from sources instead.

### Verify

```bash
readlink /usr/local/lib/icu/current            # -> /usr/local/lib/icu/76.1
/opt/php74/bin/php -m | grep -i intl           # -> intl
/opt/php74/bin/php -i | grep -i 'ICU version'  # -> ICU version => 76.1
/opt/php80/bin/php -i | grep -i 'ICU version'  # -> ICU version => 76.1
/opt/php84/bin/php -i | grep -i 'ICU version'  # -> ICU version => 76.1
```

## A build against another ICU

A PHP 7.4 or newer build compiled against an ICU other than the one this box
expects, such as a 7.4 built while ICU was pinned to 73 (`ICU version => 73.1`,
linked to the ICU 73 libraries in `/usr/local/lib`), is rebuilt against the system
ICU by the next pass, and from then on does not use those libraries.

## The weekly run

The `autoupboa weekly-system` wrapper runs one plain system upgrade, `php-max`
lines included: it never pins ICU and never idles PHP versions. Its one ICU step
concerns the marker `/var/log/boa/.php74_intl_bootstrap.active`, written only by
the weekly ICU pin cycle of earlier releases. A box still carrying it was left
pinned when that cycle was cut short, so the wrapper removes the `_ICU_FORCE_VRN`
line and the marker before its pass. A pin set by an operator carries no marker
and stays.

## Pinning ICU (`_ICU_FORCE_VRN`)

`_ICU_FORCE_VRN` (set in `/root/.barracuda.cnf`, dashed form such as `73-1`) is an
advanced, box-wide override of the ICU version. `intl` does not need it.

```bash
echo '_ICU_FORCE_VRN="73-1"' >> /root/.barracuda.cnf
barracuda up-<tier> system
```

- The pin applies to the whole box: ICU is installed at that version, and every PHP
  7.4 and newer is rebuilt against it, so 8.x lose the newer ICU's Unicode and CLDR
  data too.
- A pinned box is a custom build shape: it is refused the prebuilt PHP packages and
  builds PHP from sources.
- The pin is per box and is not carried on migration.

To return to the OS default, remove the line and run a system upgrade:

```bash
sed -i '/^_ICU_FORCE_VRN=/d' /root/.barracuda.cnf
barracuda up-<tier> system
```

ICU returns to the default version, and every PHP 7.4 and newer is rebuilt against
it in the same pass.
