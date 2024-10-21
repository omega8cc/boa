# Octopus Platforms

Octopus can install and/or support the Ægir platforms listed below.

## Note on required and supported PHP versions

Supported Drupal core versions and distributions have different PHP version requirements, while not all PHP versions out of currently supported ten versions are installed by default.

Ensure that you have corresponding PHP versions installed with barracuda before attempting to install older Drupal versions and distributions.

On hosted BOA contact your host if you need any legacy PHP installed again.

## Drupal 10

- [Drupal 10.4.x-dev](https://drupal.org/project/drupal/releases/10.4.x-dev)
- [Drupal 10.3.1](https://drupal.org/project/drupal/releases/10.3.1)
- [Drupal 10.2.7](https://drupal.org/project/drupal/releases/10.2.7)
- [Drupal 10.1.8](https://drupal.org/project/drupal/releases/10.1.8)
- [Drupal 10.0.11](https://drupal.org/project/drupal/releases/10.0.11)
- [Social 12.4.2](https://drupal.org/project/social) (10.2.6)
- [Thunder 7.3.0](https://drupal.org/project/thunder) (10.3.1)
- [Varbase 10.0.0](https://drupal.org/project/varbase) (10.3.1)
- [Varbase 9.1.3](https://drupal.org/project/varbase) (10.2.6)

## Drupal 9

- [Drupal 9.5.11](https://drupal.org/project/drupal/releases/9.5.11)
- [OpenLucius 2.0.0](https://drupal.org/project/openlucius) (9.5.11)
- [Opigno LMS 3.1.0](https://drupal.org/project/opigno_lms) (9.5.11)

## Drupal 7

- [Commerce 1.72](https://drupal.org/project/commerce_kickstart)
- [Commerce 2.77](https://drupal.org/project/commerce_kickstart)
- [Drupal 7.101.1](https://drupal.org/project/drupal/releases/7.101)
- [Ubercart 3.13](https://drupal.org/project/ubercart)

## Drupal 6

- [Pressflow 6.60.1](https://www.pressflow.org)
- [Ubercart 2.15](https://drupal.org/project/ubercart)

* All D7 platforms have been enhanced using [Drupal 7.101.1 +Extra core](https://github.com/omega8cc/7x/tree/7.x-om8)

* All D6 platforms have been enhanced using [Pressflow (LTS) 6.60.1 +Extra core](https://github.com/omega8cc/pressflow6/tree/pressflow-plus)

* All D6 and D7 platforms include some useful and performance-related contrib modules. See [docs/MODULES.md](https://github.com/omega8cc/boa/tree/5.x-dev/docs/MODULES.md) for details.

# Customize Octopus Platform List via Control File

`~/static/control/platforms.info`

This file, if it exists and contains a list of symbols used to define supported platforms, allows control/override of the value of `_PLATFORMS_LIST` variable normally defined in the `/root/.${_USER}.octopus.cnf` file, which can't be modified by the Ægir instance owner with no system root access.

**IMPORTANT**: If used, it will replace/override the value defined on initial instance install and all previous upgrades. It takes effect on every future Octopus instance upgrade, which means that you will miss all newly added distributions if they are not listed in this control file.

## Supported Values

### Drupal 10.4

- `DX4` — Drupal 10.4 prod/stage/dev

### Drupal 10.3

- `DX3` — Drupal 10.3 prod/stage/dev
- `CK3` — Commerce Kickstart v.3
- `DXP` — DXPR Marketing
- `EZC` — EzContent
- `FOS` — farmOS
- `LGV` — LocalGov
- `OCS` — OpenCulturas
- `THR` — Thunder
- `VB9` — Varbase 9
- `VBX` — Varbase 10

### Drupal 10.2

- `DX2` — Drupal 10.2 prod/stage/dev
- `OFD` — OpenFed
- `SCR` — Sector
- `SOC` — Social

### Drupal 10.1

- `DX1` — Drupal 10.1 prod/stage/dev
- `CK2` — Commerce Base v.2

### Drupal 10.0

- `DX0` — Drupal 10.0 prod/stage/dev

### Drupal 9

- `DL9` — Drupal 9 prod/stage/dev
- `OLS` — OpenLucius
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
ALL
D102P D103P SOC UC7
```
