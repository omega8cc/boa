<?php # global-bd.inc -- Backdrop-only host-wide settings

/**
 * @file
 * Backdrop-only host-wide settings, included by the Aegir Backdrop settings.php
 * template IN PLACE OF the Drupal /data/conf/global.inc.
 *
 * The Drupal global wires Valkey through $conf + Drupal cache classes
 * (Redis_Cache implements DrupalCacheInterface, include paths under
 * modules/o_contrib_seven/...) that do not exist on a Backdrop platform, so it
 * is never included for Backdrop. Backdrop has its OWN redis contrib module
 * (backdrop-contrib/redis; its Redis_Cache implements BackdropCacheInterface)
 * configured entirely through $settings. This file wires Valkey for Backdrop
 * ONLY when both the module is deployed AND Valkey answers a ping; otherwise it
 * sets nothing and Backdrop falls back to its native database cache.
 *
 * Runs inside backdrop_settings_initialize() scope, so $settings is in scope.
 *
 * Backoff: a DOWN Valkey must not cost every request a connect timeout. We reuse
 * BOA's SHARED backoff flag (the same file the Drupal global-if-valkey.inc probe
 * writes), so once any worker -- Drupal or Backdrop -- finds Valkey down, all of
 * them skip the probe for the TTL window and serve from the DB cache.
 */

// Billing suspend short-circuit -- same contract as the Drupal globals:
// /data/conf/suspended/<oct>.pid (managed by `boa suspend|unsuspend`)
// blocks every web request on the account with a 503. Guarded by SAPI
// instead of $is_backend: this file has no drush detection in scope,
// and every Backdrop backend context (bee, drush) runs under cli.
if (php_sapi_name() !== 'cli' && isset($_SERVER['DOCUMENT_ROOT'])
  && preg_match('#^/data/disk/([^/]+)/#', $_SERVER['DOCUMENT_ROOT'], $bd_suspended_m)
  && file_exists('/data/conf/suspended/' . $bd_suspended_m[1] . '.pid')) {
  header('HTTP/1.1 503 Service Unavailable');
  header('Status: 503 Service Unavailable');
  header('Retry-After: 3600');
  header('X-Accel-Expires: 60');
  header('Cache-Control: no-store, must-revalidate');
  header('Content-Type: text/html; charset=utf-8');
  header('Connection: close');
  echo '<!doctype html><title>Site temporarily unavailable</title>'
    . '<h1>Site temporarily unavailable</h1>'
    . '<p>Please check back later or contact the site owner.</p>';
  exit;
}

// Aegir owns cron: the hosting_cron queue fires core/cron.php?cron_key= on
// the per-site interval. Disable Backdrop's visit-triggered cron (config
// override, honored by the system.module threshold gate) so front-end
// traffic can never run cron -- or mask a broken web cron. Parity with
// $conf['cron_safe_threshold'] = 0 in the Drupal global include.
$config['system.core']['cron_safe_threshold'] = 0;

// The Backdrop redis module, relative to the platform docroot.
$bd_redis_dir = 'modules/redis';
$bd_redis_autoload = BACKDROP_ROOT . '/' . $bd_redis_dir . '/redis.autoload.inc';

// Only wire Valkey when the module is deployed and phpredis is loaded.
$bd_use_valkey = is_readable($bd_redis_autoload) && class_exists('Redis');

// Escape hatch: append ?noredis=1 to force the DB cache for one request.
if ($bd_use_valkey && isset($_SERVER['REQUEST_URI'])
  && strpos($_SERVER['REQUEST_URI'], 'noredis=1') !== FALSE) {
  $bd_use_valkey = FALSE;
}

// Shared backoff flag (reused from the Drupal probe): /var/tmp/fpm when it is a
// writable tmpfs, else the persistent fallback. TTL matches BOA's default.
$bd_flag_dir = '/var/tmp/fpm';
$bd_flag = (is_dir($bd_flag_dir) && is_writable($bd_flag_dir))
  ? $bd_flag_dir . '/valkey.disabled.flag'
  : '/data/conf/arch/valkey.disabled.flag';
$bd_backoff_ttl = 15;
$bd_in_backoff = (is_file($bd_flag) && (time() - (int) @filemtime($bd_flag)) < $bd_backoff_ttl);

if ($bd_use_valkey && !$bd_in_backoff) {
  $bd_valkey_socket = '/run/valkey/valkey.sock';
  $bd_valkey_base = '8';
  $bd_valkey_pass = '';
  if (is_readable('/data/conf/valkey/pass.inc')) {
    $bd_valkey_pass = trim(file_get_contents('/data/conf/valkey/pass.inc'));
  }

  // Reachability probe (short timeout) so a down Valkey never wires a cache
  // class that would then fatal every request instead of falling back.
  $bd_valkey_ok = FALSE;
  try {
    $bd_probe = new Redis();
    if (@$bd_probe->connect($bd_valkey_socket, 0, 0.7)) {
      if ($bd_valkey_pass === '' || @$bd_probe->auth($bd_valkey_pass)) {
        if (@$bd_probe->ping()) {
          $bd_valkey_ok = TRUE;
        }
      }
    }
    @$bd_probe->close();
  }
  catch (Exception $bd_e) {
    $bd_valkey_ok = FALSE;
  }

  if ($bd_valkey_ok) {
    // Recovered (or healthy): clear any shared backoff flag we can write.
    if (is_file($bd_flag) && is_writable($bd_flag)) {
      @unlink($bd_flag);
    }
    $settings['redis_client_interface'] = 'PhpRedis';
    $settings['redis_client_socket'] = $bd_valkey_socket;
    if ($bd_valkey_pass !== '') {
      $settings['redis_client_password'] = $bd_valkey_pass;
    }
    $settings['redis_client_base'] = $bd_valkey_base;
    $settings['cache_backends'][] = $bd_redis_dir . '/redis.autoload.inc';
    $settings['cache_default_class'] = 'Redis_Cache';

    // Register the module autoloader NOW, not only via cache_backends. Backdrop
    // only require()s cache_backends at the PAGE_CACHE bootstrap phase, which
    // CLI bootstraps (bee, drush) skip -- so cache() there would fatal
    // "Class Redis_Cache not found". Requiring it here (settings-init, every
    // context) makes the class available for both web and CLI. require_once is
    // idempotent with the cache_backends require above.
    require_once $bd_redis_autoload;

    // No cache_prefix override: the module already namespaces keys per site with
    // md5(db_host . db_name . db_prefix) (Redis_Client::getGlobalPrefix()),
    // which is identical in web and CLI -- so a CLI `bee cache-clear` clears the
    // very keys the web workers wrote. An explicit prefix keyed on
    // $_SERVER['SERVER_NAME'] would DIVERGE between web and CLI and break that.
  }
  else {
    // Arm the shared backoff so neither Backdrop nor Drupal re-probe for the TTL.
    @touch($bd_flag);
  }
}
