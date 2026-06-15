# DECISIONS — BOA (private-dev)

Architectural and significant implementation decisions. Append-only: never
delete or rewrite a past entry — add a superseding one instead. This file is
private-dev only and must never appear on a public branch.

---

## 2026-06-15 — Configurable ICU pin via `_ICU_FORCE_VRN`

**Decision:** Add an opt-in `_ICU_FORCE_VRN` setting (read from `/root/.barracuda.cnf`)
that pins the ICU version BOA builds/links against, resolved through a single
`_resolve_icu_target` (→ `_ICU_TARGET_VRN`). The installer (`_install_icu`,
collapsed from the former `_install_icu_modern`/`_install_icu_newer`),
`_check_php_icu_version`, and the PHP `--enable-intl` gate all read that one
resolved value. Below PHP 8.1, intl is enabled only when ICU is explicitly
pinned to a 7.4-safe major (≤ 73). Default (unset) behaviour is byte-for-byte
unchanged on every OS.

**Rationale:** A system upgrade moved a box's ICU 73 → 76. The intl gate excludes
PHP < 8.1 (7.4/8.0 cannot build intl against ICU 76+), so the routine 7.4 rebuild
silently dropped intl and live Drupal 7 sites using `Transliterator`/`locale_*`
fatalled. PHP 7.4 + ICU 73 is a native, patch-free pairing; pinning restores the
environment the site already worked in without forcing a client codebase upgrade.
Generalised into a setting so it survives rebuilds and fresh VMs. Routing the
expected-version check through the same resolver removes the installed-vs-expected
rebuild loop (installer pins 73, checker still expected the OS default 76 → forced
endless rebuild).

**Alternatives considered:**
- One-off manual 7.4 build with intl — rejected: does not survive the next
  `barracuda up` or a fresh VM.
- Enable 7.4 intl purely when ICU major ≤ 73 (capability-only, not gated on the
  explicit pin) — rejected: would silently turn on 7.4 intl on the 73-default OSes
  when unset, an unrequested behaviour change. Gating on `_ICU_FORCE_VRN` keeps it
  strictly opt-in.
- A higher safe ceiling than 73 — rejected: 73 matches `_ICU_MODERN_VRN` and BOA's
  existing tested pairing; not raised speculatively.

**Caveats (holding pattern, not permanent):**
- **Global per box.** The pin applies to ALL PHP versions, so 8.x loses ICU 76 /
  Unicode 16 / current-CLDR locale and collation behaviour. Acceptable on a known
  single-tenant workload; NOT for shared hosts.
- **Shelf life.** Once any PHP a box needs requires ICU above the pin, the box
  cannot have both. This keeps a legacy 7.4 site alive until it is moved to a newer
  PHP or retired — not a permanent setting.
- **Not migration-carried.** `.barracuda.cnf` is per box and not auto-carried on
  migration; a freshly provisioned VM builds 7.4 without intl again unless its
  runbook sets `_ICU_FORCE_VRN`. Added to the provisioning checklist for affected boxes.
- **9.0 horizon.** `mysql_native_password`-style removals aside, ICU pinning is
  source-build only and unaffected; but a future PHP needing a newer ICU than the
  pin forces the box off the pin (see shelf life).
