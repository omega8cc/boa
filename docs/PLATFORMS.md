# Octopus Platforms

Octopus can install and/or support the Ægir platforms listed below.

## Note on required and supported PHP versions

Supported Drupal core versions and distributions have different PHP version requirements, while not all PHP versions out of currently supported twelve versions are installed by default.

Ensure that you have corresponding PHP versions installed with barracuda before attempting to install older Drupal versions and distributions.

On hosted BOA contact your host if you need any legacy PHP installed again.

## Drupal 11

- [Commerce 5.1.0](https://drupal.org/project/commerce) (11.4.5)
- [Drupal 11.1.10](https://drupal.org/project/drupal/releases/11.1.10)
- [Drupal 11.2.14](https://drupal.org/project/drupal/releases/11.2.14)
- [Drupal 11.3.16](https://drupal.org/project/drupal/releases/11.3.16)
- [Drupal 11.4.5](https://drupal.org/project/drupal/releases/11.4.5)
- [Drupal CMS 2.1.3](https://drupal.org/project/cms) (11.4.5)
- [farmOS 4.0.4](https://drupal.org/project/farm) (11.3.14)
- [LocalGov 4.0.2](https://drupal.org/project/localgov) (11.4.5)
- [OpenCulturas 3.0.5](https://drupal.org/project/openculturas) (11.3.16)
- [Thunder 8.4.0](https://drupal.org/project/thunder) (11.4.5)
- [Varbase 10.1.0](https://drupal.org/project/varbase) (11.3.12)

## Drupal 10

- [Commerce v.2](https://drupal.org/project/commerce) (10.1.8)
- [Drupal 10.0.11](https://drupal.org/project/drupal/releases/10.0.11)
- [Drupal 10.1.8](https://drupal.org/project/drupal/releases/10.1.8)
- [Drupal 10.2.12](https://drupal.org/project/drupal/releases/10.2.12)
- [Drupal 10.3.14](https://drupal.org/project/drupal/releases/10.3.14)
- [Drupal 10.4.10](https://drupal.org/project/drupal/releases/10.4.10)
- [Drupal 10.5.12](https://drupal.org/project/drupal/releases/10.5.12)
- [Drupal 10.6.15](https://drupal.org/project/drupal/releases/10.6.15)
- [EzContent 2.2.15](https://drupal.org/project/ezcontent) (10.3.6)
- [OpenFed 12.2.4](https://drupal.org/project/openfed) (10.2.10)
- [Social 12.4.5](https://drupal.org/project/social) (10.2.10)

## Drupal 9

- [Drupal 9.5.11](https://drupal.org/project/drupal/releases/9.5.11)
- [Opigno LMS 3.1.0](https://drupal.org/project/opigno_lms) (9.5.11)

## Drupal 7

- [Commerce v.1](https://drupal.org/project/commerce_kickstart) (7.105.2)
- [Drupal 7.105.2](https://docs.tag1.com/faqs/)
- [Ubercart 3.13](https://drupal.org/project/ubercart) (7.105.2)

## Drupal 6

- [Pressflow 6.60.1](https://www.pressflow.org)
- [Ubercart 2.15](https://drupal.org/project/ubercart) (6.60.1)

## Backdrop CMS

- [Backdrop CMS (latest stable release)](https://backdropcms.org)

* Backdrop platforms track the newest release automatically (the mirror's `backdrop.txt` stamp selects the versioned `backdrop-<ver>.tar.gz` to fetch, managed like the Drupal core tarballs), so there is no per-version pin to maintain.
* Each Backdrop platform gets the Valkey/Redis object-cache module through the shared, centrally updated `o_contrib_backdrop` bundle, symlinked in on platform verify and repaired nightly — used per site when Valkey is available, otherwise the site falls back to Backdrop's database cache.
* Backdrop sites are managed with both `bee` (the native Backdrop CLI) and Drush 8 (via the backdrop-drush-extension).
* Ships ON by default: Backdrop platforms build whenever the platform list includes the `BDR` symbol (or `ALL`); set `_BACKDROP_SUPPORT=NO` in the Octopus config to opt an instance out.

* All D7 platforms have been enhanced using [Drupal 7.105.2 +Extra core](https://github.com/omega8cc/7x/tree/7.x-om8)

* All D6 platforms have been enhanced using [Pressflow (LTS) 6.60.1 +Extra core](https://github.com/omega8cc/pressflow6/tree/pressflow-plus)

* All D6 and D7 platforms include some useful and performance-related contrib modules. See [docs/MODULES.md](https://github.com/omega8cc/boa/tree/5.x-pro/docs/MODULES.md) for details.

# Customize Octopus Platform List via Control File

`~/static/control/platforms.info`

This file, if it exists and contains a list of symbols used to define supported platforms, allows control/override of the value of `_PLATFORMS_LIST` variable normally defined in the `/root/.${_USER}.octopus.cnf` file, which can't be modified by the Ægir instance owner with no system root access.

**IMPORTANT**: If used, it will replace/override the value defined on initial instance install and all previous upgrades. It takes effect on every future Octopus instance upgrade, which means that you will miss all newly added distributions if they are not listed in this control file.

## Supported Values

### Drupal 11.4

- `DE4` — Drupal 11.4 prod/stage/dev
- `CK3` — Commerce v.3
- `CMS` — Drupal CMS
- `LGV` — LocalGov
- `THR` — Thunder

### Drupal 11.3

- `DE3` — Drupal 11.3 prod/stage/dev
- `FOS` — farmOS
- `OCS` — OpenCulturas
- `VBX` — Varbase 10

### Drupal 11.2

- `DE2` — Drupal 11.2 prod/stage/dev

### Drupal 11.1

- `DE1` — Drupal 11.1 prod/stage/dev

### Drupal 10.6

- `DX6` — Drupal 10.6 prod/stage/dev

### Drupal 10.5

- `DX5` — Drupal 10.5 prod/stage/dev

### Drupal 10.4

- `DX4` — Drupal 10.4 prod/stage/dev

### Drupal 10.3

- `DX3` — Drupal 10.3 prod/stage/dev
- `EZC` — EzContent

### Drupal 10.2

- `DX2` — Drupal 10.2 prod/stage/dev
- `OFD` — OpenFed
- `SOC` — Social

### Drupal 10.1

- `DX1` — Drupal 10.1 prod/stage/dev
- `CK2` — Commerce v.2

### Drupal 10.0

- `DX0` — Drupal 10.0 prod/stage/dev

### Drupal 9

- `DL9` — Drupal 9 prod/stage/dev
- `OPG` — Opigno LMS

### Drupal 7

- `DL7` — Drupal 7 prod/stage/dev
- `CK1` — Commerce v.1
- `UC7` — Ubercart

### Drupal 6

- `DL6` — Pressflow (LTS) prod/stage/dev
- `UC6` — Ubercart

You can also use the special keyword `ALL` instead of any other symbols to have all available platforms installed, including newly added platforms in all future BOA system releases.

### Examples:

```
DE2 DX5 SOC UC7
```

```
ALL
```
