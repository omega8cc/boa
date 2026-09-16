<?php # global settings.php


/**
 * Backdrop Valkey/Redis wiring -- the Backdrop sibling of global-valkey.inc.
 *
 * Runs after the shared probe (global-if-valkey.inc / global-if-redis.inc),
 * so $valkey_up, $use_valkey, the connection targets and $auth_pass are in
 * scope, and every probe-tuning INI key (redis_connect_timeout,
 * redis_read_timeout, redis_backoff_ttl, redis_probe_retry,
 * redis_flush_apcu_on_recovery, redis_debug_header, redis_debug) is honoured
 * on Backdrop through the very code the Drupal chain runs. The shared
 * backoff flag is armed and cleared with the same accounting on both cores,
 * so a Backdrop request can no longer clear it out from under a Drupal
 * worker's recovery flush.
 *
 * Backdrop runs backdrop-contrib/redis (its Redis_Cache implements
 * BackdropCacheInterface), configured entirely through $settings, so the
 * Drupal global-valkey.inc ($conf + Drupal cache classes) is never included
 * on this chain. This file runs inside backdrop_settings_initialize() scope,
 * where $settings, $conf and $config are the variables settings.php writes.
 *
 * Deliberately NOT ported from the D7 block, each for a Backdrop reason:
 *   - cache_prefix: the module namespaces keys per site with
 *     md5(db_host . db_name . db_prefix) (Redis_Client::getGlobalPrefix()),
 *     identical in web and CLI, so a CLI `bee cache-clear` clears the very
 *     keys the web workers wrote; a SERVER_NAME-derived prefix would diverge
 *     between the two and break that.
 *   - redis_flush_mode*: the Backdrop module knows normal and sharded
 *     flushing only (no D7 modes 1/2, no per-bin modes); only the permanent
 *     items TTL half of redis_flush_forced_mode has a home.
 *   - redis_scan_delete: the module has no SCAN-delete option;
 *     redis_scan_enable is read for its X-Ini header only.
 *   - page_cache_maximum_age / page_cache_invoke_hooks: on Backdrop the first
 *     is the page cache entry lifetime itself (D7's cache_lifetime and the
 *     Cache-Control max-age folded into one key; 0 would expire every entry
 *     on creation), and the second re-enables the deprecated hook_boot() on
 *     cached pages; both keep core's defaults.
 *   - path_alias_admin_blacklist: read through variable_get(), and Backdrop
 *     rebuilds $conf from the variable table at BOOTSTRAP_VARIABLES, so a
 *     settings-time $conf write never reaches it; the module default stands.
 *   - Redis_CacheCompressed: the two classes cannot read each other's
 *     entries, so a class switch on a running site is a change of its own
 *     (see the cache_default_class comment below); the plain class stays.
 *
 * Must remain PHP 5.6 compatible (shared-tree file).
 */
if ($valkey_up && $use_valkey && !$custom_cache && defined('BACKDROP_ROOT')) {
  $cache_valkey = FALSE;
  // The Backdrop redis module, relative to the platform docroot. Prefer the
  // canonical shared bundle (modules/o_contrib_backdrop, symlinked into every
  // platform on verify and updatable in place fleet-wide), then fall back to
  // the originally shipped baked copy so platforms built from older
  // backdrop.tar.gz keep their cache wiring without a reverify.
  $bd_redis_dir = 'modules/o_contrib_backdrop/redis_backdrop';
  if (!is_readable(BACKDROP_ROOT . '/' . $bd_redis_dir . '/redis.autoload.inc')) {
    $bd_redis_dir = 'modules/redis';
  }
  if (is_readable(BACKDROP_ROOT . '/' . $bd_redis_dir . '/redis.autoload.inc')) {
    $cache_valkey = TRUE;
    $cache_redis_path = $bd_redis_dir . '/redis.autoload.inc';
    $cache_lock_path = $bd_redis_dir . '/inc/redis.lock.inc';
    $cache_path_path = $bd_redis_dir . '/inc/redis.path.inc';
    if ($is_dev && !$is_backend) {
      header("X-Valkey-Autoload-Is-Readable: " . $cache_redis_path);
    }
  }
  if ($cache_valkey) {
    // Connection: the transport the probe actually answered on -- a stale
    // socket inode with nothing behind it must not be handed to the module
    // just because the file is readable -- and the password the probe
    // authenticated with (/data/conf/valkey/pass.inc, else the literal the
    // upgrade pass wrote into the probe file).
    $settings['redis_client_interface'] = 'PhpRedis';
    if (isset($valkey_transport) && $valkey_transport === 'socket') {
      $settings['redis_client_socket'] = $valkey_socket_path;
    }
    else {
      $settings['redis_client_host'] = $valkey_host;
      $settings['redis_client_port'] = $valkey_port;
    }
    if (isset($auth_pass) && $auth_pass !== '') {
      $settings['redis_client_password'] = $auth_pass;
    }
    $settings['redis_client_base'] = '8';

    if ($all_ini['redis_lock_enable']) {
      $redis_lock = TRUE;
    }
    if ($all_ini['redis_path_enable']) {
      $redis_path = TRUE;
    }
    // Both includes are required by core as BACKDROP_ROOT . '/' . <value>,
    // hence the docroot-relative paths.
    if ($redis_lock && is_readable(BACKDROP_ROOT . '/' . $cache_lock_path)) {
      $settings['lock_inc']                     = $cache_lock_path;
      if ($is_dev && !$is_backend) {
        header("X-Valkey-Lock-Is-Readable: " . $cache_lock_path);
      }
    }
    if ($redis_path && is_readable(BACKDROP_ROOT . '/' . $cache_path_path)) {
      $settings['path_inc']                     = $cache_path_path;
      // D7 also sets path_alias_admin_blacklist FALSE. The Backdrop module
      // reads it through variable_get(), and Backdrop rebuilds $conf from
      // the variable table at BOOTSTRAP_VARIABLES, so nothing settings.php
      // writes there survives: the module default (TRUE) stands on Backdrop.
      if ($is_dev && !$is_backend) {
        header("X-Valkey-Path-Is-Readable: " . $cache_path_path);
      }
    }
    // The plain class, as before this chain existed. The module also ships
    // Redis_CacheCompressed (D7's gzip posture), but the two classes cannot
    // read each other's entries and every worker of a pool switches on its
    // own opcache clock (up to 60 s apart), so changing the class on a
    // running site means a window of fatals, and any rollback the same. A
    // switch needs its own keyspace (redis_prefix) and its own change.
    $settings['cache_default_class']            = 'Redis_Cache';
    $settings['cache_backends'][]               = $cache_redis_path;

    // Register the module autoloader NOW, not only via cache_backends.
    // Backdrop only require()s cache_backends at the PAGE_CACHE bootstrap
    // phase, which CLI bootstraps (bee, drush) skip -- so cache() there would
    // fatal "Class Redis_Cache not found". Requiring it here (settings-init,
    // every context) makes the class available for both web and CLI.
    // require_once is idempotent with the cache_backends require above.
    require_once BACKDROP_ROOT . '/' . $cache_redis_path;

    if ($all_ini['redis_flush_forced_mode']) {
      $settings['redis_perm_ttl']               = 86400; // 24 hours max, as on D6/D7
      if ($is_dev && !$is_backend) {
        header("X-Valkey-Flush-Forced-Mode: Forced");
      }
    }
    if ($all_ini['redis_exclude_bins'] && !is_readable('/data/conf/clstr.cnf')) {
      $excludes = array();
      $excludes = explode(",", $all_ini['redis_exclude_bins']);
      foreach ($excludes as $exclude) {
        $exclude = rtrim($exclude);
        $exclude = ltrim($exclude);
        // Backdrop's cache() strips a leading cache_ from the bin name BEFORE
        // it looks the class up (core/includes/cache.inc), and core passes
        // bare names ('form', 'page', 'menu'), so the working key is
        // cache_class_<bare-bin>; the D7 spelling with the prefix is inert.
        $bin_exclude = 'cache_class_' . preg_replace('/^cache_/', '', $exclude);
        $settings[$bin_exclude] = 'BackdropDatabaseCache';
        if ($is_dev && !$is_backend) {
          header("X-Ini-Valkey-Exclude-Bin-" . $exclude . ": " . $bin_exclude);
        }
      }
    }
  }
}

/**
 * Always-on, non-sensitive backend observability (ini: redis_debug_header).
 *
 * Reports which backend served the structured-cache bins on THIS request,
 * pairing with X-Cache-State from the shared probe. Backdrop has no APCu
 * front layer, so the answer is db or redis, never chainedfast.
 */
if (isset($all_ini['redis_debug_header']) && $all_ini['redis_debug_header'] &&
    empty($is_backend) && !headers_sent()) {
  $vk_backend = 'db';
  if (!empty($cache_valkey)) {
    $vk_backend = 'redis';
  }
  header('X-Cache-Backend: ' . $vk_backend);
}
