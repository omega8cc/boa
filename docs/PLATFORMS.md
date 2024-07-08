
# Octopus Platforms

Octopus can install and/or support the Aegir platforms listed below:

## Drupal 10

- [Drupal 10.2.4](https://drupal.org/project/drupal/releases/10.2.4)
- [Drupal 10.1.8](https://drupal.org/project/drupal/releases/10.1.8)
- [Drupal 10.0.11](https://drupal.org/project/drupal/releases/10.0.11)
- [Social 12.2.2](https://drupal.org/project/social) (10.2.4)
- [Thunder 7.2.0](https://drupal.org/project/thunder) (10.2.4)
- [Varbase 9.1.1](https://drupal.org/project/varbase) (10.2.4)

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

This file, if it exists and contains a list of symbols used to define supported platforms, allows control/override of the value of `_PLATFORMS_LIST` variable normally defined in the `/root/.${_USER}.octopus.cnf` file, which can't be modified by the Aegir instance owner with no system root access.

**IMPORTANT**: If used, it will replace/override the value defined on initial instance install and all previous upgrades. It takes effect on every future Octopus instance upgrade, which means that you will miss all newly added distributions if they are not listed in this control file.

## Supported Values

### Drupal 10.2 based

- `D102P D102S D102D` — Drupal 10.2 prod/stage/dev

### Drupal 10.1 based

- `D101P D101S D101D` — Drupal 10.1 prod/stage/dev
- `THR` — Thunder
- `VBE` — Varbase

### Drupal 10.0 based

- `D100P D100S D100D` — Drupal 10.0 prod/stage/dev

### Drupal 9 based

- `D9P D9S D9D` — Drupal 9 prod/stage/dev
- `OLS` — OpenLucius
- `OPG` — Opigno LMS
- `SOC` — Social

### Drupal 7 based

- `D7P D7S D7D` — Drupal 7 prod/stage/dev
- `CME` — Commerce v.2
- `DCE` — Commerce v.1
- `UC7` — Ubercart

### Drupal 6 based

- `D6P D6S D6D` — Pressflow (LTS) prod/stage/dev
- `UCT` — Ubercart

You can also use the special keyword `ALL` instead of any other symbols to have all available platforms installed, including newly added platforms in all future BOA system releases.

### Examples:

```
ALL
D101P D101S SOC
```
