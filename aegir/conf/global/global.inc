<?php # global settings.php

/**
 * BOA global settings dispatcher.
 *
 * Since 2024-07 the provision settings templates include the per-core
 * chain directly — /data/conf/global/global-<core>.inc — with this file
 * only as a fallback. This file remains the live include path for:
 *   - settings.php files not re-generated (re-verified) since then,
 *     which still include <aegir include_path>/global.inc, a symlink
 *     kept pointing at /data/conf/global.inc,
 *   - the current templates' fallback when the per-core chain is
 *     unreadable.
 *
 * It used to carry a full second copy of the chain logic, which silently
 * drifted from the maintained partials (probe timeouts, D8+ TTL emission,
 * anon session detection, D11 module dir resolution, observability
 * headers). To make drift impossible it now only detects the core and
 * hands off to the exact same chain the current templates use. The chain
 * is always deployed together with this file by _global_inc_conf_update()
 * (partials first, this file last), so it is present wherever this
 * dispatcher is.
 *
 * Keep all settings logic out of this file — it must stay a pure
 * dispatcher. Must remain PHP 5.6 compatible (legacy servers).
 */

/**
 * Core detection; cwd is the platform root when settings.php runs.
 * Mirrors the detection logic this file carried before. Unmatched or
 * unrecognized layouts fall back to '7' as before (generic pre-D8
 * settings; the module wiring stays inert via the is_readable() guards
 * inside the chain).
 */
$_boa_core_probe = '7';
if (file_exists('web.config') || file_exists('index.php')) {
  if (file_exists('core')) {
    if (file_exists('vendor/symfony') ||
      file_exists('core/vendor/symfony') ||
      file_exists('autoload.php')) {
      $_boa_core_probe = '8';
      if (file_exists('core/themes/olivero') && file_exists('core/themes/classy')) {
        $_boa_core_probe = '9';
      }
      if (file_exists('core/themes/olivero') && !file_exists('core/themes/classy')) {
        $_boa_core_probe = '10';
      }
      if (file_exists('core/modules/workspaces_ui') && !file_exists('web.config')) {
        $_boa_core_probe = '11';
      }
    }
    else {
      // Backdrop CMS: core/ present without a Composer autoloader.
      $_boa_core_probe = 'bd';
    }
  }
  elseif (file_exists('modules/path_alias_cache')) {
    $_boa_core_probe = '6';
  }
}

$_boa_core_inc = '/data/conf/global/global-' . $_boa_core_probe . '.inc';
if (is_readable($_boa_core_inc)) {
  include_once($_boa_core_inc);
}
