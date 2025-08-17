# Composer Usage in BOA Codebases

This document explains correct and incorrect Composer usage in the context of Ægir-powered Drupal 10 platforms managed by BOA (Barracuda Octopus Ægir), as well as safe Composer workflows for standalone Composer-based sites.

Composer is powerful, but misuse can result in broken platforms, partial upgrades, or corrupted deployments.

You should think about Composer like it was Drush Make replacement, and you should not re-build nor upgrade the codebase on a platform with sites already hosted. Just use it to build new codebases and then add them as platforms when the build works without errors.

---

## Table of Contents

1. [Immutable Codebase Workflow (Safe & Supported)](#1-immutable-codebase-workflow-safe--supported)
2. [Quick & Dirty Composer Usage (Unsafe & Unsupported)](#2-quick--dirty-composer-usage-unsafe--unsupported)
3. [Developer Shortcut: Safe-ish Platform Clone](#3-developer-shortcut-safe-ish-platform-clone)
4. [Site-local Drush (vdrush) for Direct Updates](#4-site-local-drush-vdrush-for-direct-updates)
5. [Composer Sites Managed Directly – Module Updates](#5-composer-sites-managed-directly--module-updates)
6. [Composer Branch Switching – Safe Handling After Git Checkout](#6-composer-branch-switching--safe-handling-after-git-checkout)
7. [Summary](#7-summary)

---

## 1. Immutable Codebase Workflow (Safe & Supported)

**Use this method for all production work.** This is the **only officially supported** and reproducible Composer workflow for Ægir-managed platforms.

BOA platforms are **immutable** once deployed. Composer must never be used on platforms already powering Ægir-hosted sites.

### ✅ Allowed Composer usage (before adding to Ægir):

```bash
composer create-project drupal/recommended-project:^10 myplatform
cd myplatform

composer require drupal/module_name
composer update drupal/module_name --with-dependencies

composer install --no-interaction --optimize-autoloader
```

Then:
- Commit `composer.json`, `composer.lock`, and any scaffolded files
- Add to Ægir as a new platform
- Migrate test sites
- Migrate live sites after successful verification

📚 Learn more: [Safe Upgrade Workflow](https://learn.omega8.cc/your-drupal-site-upgrade-safe-workflow-298)

---

## 2. Quick & Dirty Composer Usage (Unsafe & Unsupported)

**NOT SUPPORTED — but documented for transparency.**
Used by some developers who ignore Ægir’s platform immutability.

### ⚠️ Risks:
- Overwrites `core`, `vendor`, scaffolded files
- Breaks symlinks, permissions, autoloaders
- Causes unpredictable site behavior

### ⚠️ Example (DANGEROUS):

```bash
cd ~/static/path/to/platform-app-root
rm -rf core vendor composer.lock
composer install --no-dev
composer require drupal/module_name
```

Use [vdrush](#4-site-local-drush-vdrush-for-direct-updates) to update individual sites afterward.

---

## 3. Developer Shortcut: Safe-ish Platform Clone

To test module updates or patches quickly:

```bash
cp -a ~/static/path/to/platform ~/static/path/to/platform-new
cd ~/static/path/to/platform-new

composer clear-cache
composer require drupal/new_module
composer update drupal/existing_module --with-dependencies
composer install --no-interaction --optimize-autoloader
```

- Add new platform in Ægir
- Migrate a test site
- If stable, migrate remaining sites
- Later remove the old platform

---

## 4. Site-local Drush (vdrush) for Direct Updates

If Composer is used outside Ægir, you must update each site manually:

```bash
cd ~/static/path/to/platform-app-root
vdrush @site-alias updb
vdrush @site-alias cr
```

📚 Learn more:
[DRUSH-CLI.md – Site-local Drush](https://github.com/omega8cc/boa/blob/5.x-pro/docs/DRUSH-CLI.md#steps-to-use-site-local-drush)

---

## 5. Composer Sites Managed Directly – Module Updates

For Composer-managed Drupal 10 sites **not using Ægir workflow**, here's the simplest way to update one or two modules (e.g., for security releases).

### ✅ Update process:

```bash
composer clear-cache
cd ~/static/path/to/platform-app-root
composer update drupal/module_name --with-dependencies
vdrush @site-alias updb
vdrush @site-alias cr
```

### 🔐 Lock to specific version (optional):
```bash
composer require drupal/module_name:^1.8 --update-with-dependencies
```

### 🧠 Tips:
- Preview first:
  ```bash
  composer update drupal/module_name --with-dependencies --dry-run
  ```
- Check what’s outdated:
  ```bash
  composer outdated drupal/*
  ```

---

## 6. Composer Branch Switching – Safe Handling After Git Checkout

Switching Git branches in a Composer-managed project can break dependencies if `vendor/` and `composer.lock` aren't reset.

### ⚠️ Problem:

```bash
composer install
git checkout feature/new-ui
composer install  # ⛔ may fail!
```

Result: version mismatches, broken autoloaders, partial installs.

---

### ✅ Correct workflow:

```bash
rm -rf vendor/
composer clear-cache
composer install --no-dev
```

This ensures:
- Clean dependency state
- `composer.lock` matches `vendor/`
- No leftover packages from previous branch

💡 Avoid switching branches with uncommitted Composer changes.

---

## 7. Summary

| Scenario                             | Composer Use Allowed? | Notes |
|--------------------------------------|------------------------|-------|
| Building a new platform              | ✅ Yes                | Fully supported |
| Platform already in use by Ægir     | ❌ No                 | Never use Composer |
| Cloned platform for dev/testing      | ⚠️ With care         | Register in Ægir separately |
| Quick hacks on live platform         | ⚠️ Very risky         | Unsupported |
| Updating standalone Composer site    | ✅ Yes                | Follow best practices |
| Applying DB updates per site         | ✅ Use `vdrush`       | Required after Composer hacks |
| Switching Git branches               | ⚠️ Requires cleanup   | Always clear cache + remove vendor |

---

**Composer is a build-time tool — not a runtime update manager.
In Ægir, platforms are immutable once deployed.
Always test changes before applying them to live sites.**

_Last updated: 2025-04-03_


