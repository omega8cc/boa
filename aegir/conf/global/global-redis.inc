<?php # global settings.php


/**
 * Use Redis caching and lock support only for d6 and d7 profiles
 */
if ($redis_up && $use_redis && !$custom_cache) {
  $cache_backport = FALSE;
  $cache_redis = FALSE;
  $all_ini['redis_use_modern'] = TRUE;
  if ($all_ini['redis_use_modern']) {
    if ($drupal_core >= 8) {
      $redis_dirname = 'redis_eight';
      if (!$all_ini['redis_old_eight_mode']) {
        $redis_dirname = 'redis_compr';
        $redis_comprs = TRUE;
      }
      if ($drupal_core === 9 || $drupal_core === 10) {
        $redis_dirname = 'redis_nine_ten';
        $redis_comprs = TRUE;
        if ($all_ini['redis_old_nine_mode']) {
          $redis_dirname = 'redis_compr';
        }
      }
    }
    else {
      $redis_dirname = 'redis_edge';
    }
    if ($is_dev && !$is_backend) {
      header("X-Redis-Version-Is: Modern");
      header("X-Redis-Dir-Is: " . $redis_dirname);
    }
    if ($all_ini['redis_flush_forced_mode']) {
      if ($drupal_core >= 8) {
        $settings['redis_perm_ttl']                 = 86400; // 24 hours max
        $settings['redis_flush_mode']               = 1; // Redis default is 0
        $settings['redis_flush_mode_cache_page']    = 2; // Redis default is 1
        $settings['redis_flush_mode_cache_block']   = 2; // Redis default is 1
        $settings['redis_flush_mode_cache_menu']    = 2; // Redis default is 0
        $settings['redis_flush_mode_cache_metatag'] = 2; // Redis default is 0
      }
      else {
        $conf['redis_perm_ttl']                 = 86400; // 24 hours max
        $conf['redis_flush_mode']               = 1; // Redis default is 0
        $conf['redis_flush_mode_cache_page']    = 2; // Redis default is 1
        $conf['redis_flush_mode_cache_block']   = 2; // Redis default is 1
        $conf['redis_flush_mode_cache_menu']    = 2; // Redis default is 0
        $conf['redis_flush_mode_cache_metatag'] = 2; // Redis default is 0
      }
      // See http://bit.ly/1drmi35 for more information
      if ($is_dev && !$is_backend) {
        header("X-Redis-Flush-Forced-Mode: Forced");
      }
    }
  }
  else {
    $redis_dirname = 'redis';
    if ($is_dev && !$is_backend) {
      header("X-Redis-Version-Is: Legacy");
      header("X-Redis-Dir-Is: " . $redis_dirname);
    }
  }
  if ($drupal_core >= 8) {
    if (file_exists('sites/' . $_SERVER['SERVER_NAME'] . '/.redisLegacyOff')) {
      if ($is_dev && !$is_backend) {
        header("X-Redis-Off-Ctrl-Exists: .redisLegacyOff");
      }
    }
    else {
      if (is_readable('sites/' . $_SERVER['SERVER_NAME'] . '/files/development.services.yml')) {
        if ($is_dev && !$is_backend) {
          header("X-Dev-Services-Yml-Is-Readable: development.services.yml");
        }
      }
      else {
        if (is_readable('modules/o_contrib_eight/' . $redis_dirname . '/example.services.yml')) {
          $cache_redis = TRUE;
          $example_services_path = 'modules/o_contrib_eight/' . $redis_dirname . '/example.services.yml';
          $cache_gzip_path = 'modules/o_contrib_eight/' . $redis_dirname . '/lib/Redis/CacheCompressed.php';
          if ($is_dev && !$is_backend) {
            header("X-Example-Services-Is-Readable: " . $example_services_path);
          }
        }
        if (is_readable('modules/o_contrib_eight/' . $redis_dirname . '/redis.services.yml')) {
          $cache_redis = TRUE;
          $redis_services_path = 'modules/o_contrib_eight/' . $redis_dirname . '/redis.services.yml';
          if ($is_dev && !$is_backend) {
            header("X-Redis-Services-Is-Readable: " . $redis_services_path);
          }
        }
        if (is_readable('modules/o_contrib_nine/' . $redis_dirname . '/example.services.yml')) {
          $cache_redis = TRUE;
          $example_failover_path = 'modules/o_contrib_nine/' . $redis_dirname . '/example.failover.services.yml';
          $example_services_path = 'modules/o_contrib_nine/' . $redis_dirname . '/example.services.yml';
          $cache_gzip_path = 'modules/o_contrib_nine/' . $redis_dirname . '/lib/Redis/CacheCompressed.php';
        }
        if (is_readable('modules/o_contrib_nine/' . $redis_dirname . '/redis.services.yml')) {
          $cache_redis = TRUE;
          $redis_services_path = 'modules/o_contrib_nine/' . $redis_dirname . '/redis.services.yml';
          if ($is_dev && !$is_backend) {
            header("X-Redis-Services-Is-Readable: " . $redis_services_path);
          }
        }
        if (is_readable('modules/o_contrib_ten/' . $redis_dirname . '/example.services.yml')) {
          $cache_redis = TRUE;
          $example_failover_path = 'modules/o_contrib_ten/' . $redis_dirname . '/example.failover.services.yml';
          $example_services_path = 'modules/o_contrib_ten/' . $redis_dirname . '/example.services.yml';
          $cache_gzip_path = 'modules/o_contrib_ten/' . $redis_dirname . '/lib/Redis/CacheCompressed.php';
        }
        if (is_readable('modules/o_contrib_ten/' . $redis_dirname . '/redis.services.yml')) {
          $cache_redis = TRUE;
          $redis_services_path = 'modules/o_contrib_ten/' . $redis_dirname . '/redis.services.yml';
          if ($is_dev && !$is_backend) {
            header("X-Redis-Services-Is-Readable: " . $redis_services_path);
          }
        }
      }
    }
  }
  elseif ($drupal_core === 7) {
    if (is_readable('modules/o_contrib_seven/' . $redis_dirname . '/redis.autoload.inc')) {
      $cache_redis = TRUE;
      $cache_backport = FALSE;
      $cache_redis_path = 'modules/o_contrib_seven/' . $redis_dirname . '/redis.autoload.inc';
      $cache_lock_path = 'modules/o_contrib_seven/' . $redis_dirname . '/redis.lock.inc';
      $cache_path_path = 'modules/o_contrib_seven/' . $redis_dirname . '/redis.path.inc';
      $cache_gzip_path = 'modules/o_contrib_seven/' . $redis_dirname . '/lib/Redis/CacheCompressed.php';
      if ($is_dev && !$is_backend) {
        header("X-Redis-Autoload-Is-Readable: " . $cache_redis_path);
      }
    }
    if ($all_ini['autoslave_enable']) {
      if (is_readable('modules/o_contrib_seven/autoslave/autoslave.cache.inc') &&
        is_readable('includes/database/autoslave/database.inc')) {
        $use_auto_se = TRUE;
        $gzip_mode = FALSE;
        $cache_backport = FALSE;
        $auto_se_path = 'modules/o_contrib_seven/autoslave/autoslave.cache.inc';
        if ($is_dev && !$is_backend) {
          header("X-AutoSlave-Cache-Is-Readable: " . $auto_se_path);
        }
      }
    }
    if ($all_ini['cache_consistent_enable']) {
      if (is_readable('modules/o_contrib_seven/cache_consistent/cache_consistent.inc')) {
        $use_cache_ct = TRUE;
        $gzip_mode = FALSE;
        $cache_backport = FALSE;
        $cache_ct_path = 'modules/o_contrib_seven/cache_consistent/cache_consistent.inc';
        if ($is_dev && !$is_backend) {
          header("X-CacheConsistent-Is-Readable: " . $cache_ct_path);
        }
      }
    }
  }
  elseif ($drupal_core === 6) {
    if (is_readable('modules/o_contrib/cache_backport/cache.inc')) {
      $cache_backport = TRUE;
      $cache_backport_path = 'modules/o_contrib/cache_backport/cache.inc';
      if ($is_dev && !$is_backend) {
        header("X-Redis-Cache-Backport-Is-Readable: " . $cache_backport_path);
      }
    }
    if (is_readable('modules/o_contrib/' . $redis_dirname . '/redis.autoload.inc')) {
      $cache_redis = TRUE;
      $cache_redis_path = 'modules/o_contrib/' . $redis_dirname . '/redis.autoload.inc';
      $cache_lock_path = 'modules/o_contrib/' . $redis_dirname . '/redis.lock.inc';
      $cache_path_path = 'modules/o_contrib/' . $redis_dirname . '/redis.path.inc';
      $cache_gzip_path = 'modules/o_contrib/' . $redis_dirname . '/lib/Redis/CacheCompressed.php';
      if ($is_dev && !$is_backend) {
        header("X-Redis-Autoload-Is-Readable: " . $cache_redis_path);
      }
    }
  }
  if ($cache_redis) {
    if ($drupal_core >= 8) {
      if (is_readable('modules/o_contrib_ten/' . $redis_dirname . '/redis.services.yml')) {
        $class_loader->addPsr4('Drupal\\redis\\', 'modules/o_contrib_ten/' . $redis_dirname . '/src');
      }
      elseif (is_readable('modules/o_contrib_nine/' . $redis_dirname . '/redis.services.yml')) {
        $class_loader->addPsr4('Drupal\\redis\\', 'modules/o_contrib_nine/' . $redis_dirname . '/src');
      }
      else {
        $class_loader->addPsr4('Drupal\\redis\\', 'modules/o_contrib_eight/' . $redis_dirname . '/src');
      }
      $settings['redis.connection']['interface'] = 'PhpRedis';
      $settings['redis.connection']['host']      = '127.0.0.1';
      $settings['redis.connection']['port']      = '6379';
      $settings['redis.connection']['password']  = 'isfoobared';
      $settings['redis.connection']['base']      = '8';
      $settings['cache_prefix']                  = $this_prefix;
      $settings['cache']['default']              = 'cache.backend.redis';
      if (!is_readable('/data/conf/clstr.cnf')) {
        $settings['cache']['bins']['bootstrap']  = 'cache.backend.database';
        $settings['cache']['bins']['discovery']  = 'cache.backend.database';
        $settings['cache']['bins']['config']     = 'cache.backend.database';
      }
      if (is_readable($example_failover_path)) {
        $settings['container_yamls'][]           = $example_failover_path;
        $settings['redis.failover']              = TRUE;
        if ($is_dev && !$is_backend) {
          header("X-Redis-Failover-Is-Readable: " . $example_failover_path);
        }
      }
      elseif (is_readable($example_services_path)) {
        $settings['container_yamls'][]           = $example_services_path;
        if ($is_dev && !$is_backend) {
          header("X-Redis-Example-Is-Readable: " . $example_services_path);
        }
      }
      if (is_readable($redis_services_path)) {
        $settings['container_yamls'][]           = $redis_services_path;
        if ($is_dev && !$is_backend) {
          header("X-Redis-Services-Is-Readable: " . $redis_services_path);
        }
      }
      $settings['queue_default']                 = 'queue.redis';
      if ($redis_comprs) {
        $settings['redis_compress_length']       = 100;
        $settings['redis_compress_level']        = 5;
      }
      $settings['cache']['bins']['state']        = 'cache.backend.redis';
      $settings['state_cache']                   = TRUE;
      $settings['bootstrap_container_definition'] = [
        'parameters' => [],
        'services' => [
          'redis.factory' => [
            'class' => 'Drupal\redis\ClientFactory',
          ],
          'cache.backend.redis' => [
            'class' => 'Drupal\redis\Cache\CacheBackendFactory',
            'arguments' => ['@redis.factory', '@cache_tags_provider.container', '@serialization.phpserialize'],
          ],
          'cache.container' => [
            'class' => '\Drupal\redis\Cache\PhpRedis',
            'factory' => ['@cache.backend.redis', 'get'],
            'arguments' => ['container'],
          ],
          'cache_tags_provider.container' => [
            'class' => 'Drupal\redis\Cache\RedisCacheTagsChecksum',
            'arguments' => ['@redis.factory'],
          ],
          'serialization.phpserialize' => [
            'class' => 'Drupal\Component\Serialization\PhpSerialize',
          ],
        ],
      ];
    }
    else {
      if ($cache_backport) {
        $conf['cache_inc']                      = $cache_backport_path;
      }
      if ($all_ini['redis_use_modern']) {
        if ($all_ini['redis_lock_enable']) {
          $redis_lock = TRUE;
        }
        if ($all_ini['redis_path_enable']) {
          $redis_path = TRUE;
        }
      }
      if (is_readable($cache_lock_path) && $redis_lock) {
        $conf['lock_inc']                       = $cache_lock_path;
        if ($is_dev && !$is_backend) {
          header("X-Redis-Lock-Is-Readable: " . $cache_lock_path);
        }
      }
      if (is_readable($cache_path_path) && $redis_path) {
        $conf['path_inc']                       = $cache_path_path;
        $conf['path_alias_admin_blacklist']     = FALSE;
        if ($is_dev && !$is_backend) {
          header("X-Redis-Path-Is-Readable: " . $cache_path_path);
        }
      }
      if ($all_ini['redis_scan_enable']) {
        $conf['redis_scan_delete']              = TRUE;
        $gzip_mode = FALSE;
      }
      else {
        if (is_readable($cache_gzip_path)) {
          $gzip_mode = TRUE;
        }
        else {
          $gzip_mode = FALSE;
        }
      }
      if ($gzip_mode) {
        $conf['cache_default_class']            = 'Redis_CacheCompressed';
      }
      else {
        $conf['cache_default_class']            = 'Redis_Cache';
      }
      $conf['cache_backends'][]                 = $cache_redis_path;
      if ($use_auto_se) {
        $conf['cache_backends'][]               = $auto_se_path;
        $conf['cache_default_class']            = 'AutoslaveCache';
        $conf['autoslave_cache_default_class']  = 'Redis_Cache';
      }
      if ($use_cache_ct) {
        $conf['cache_backends'][]               = $cache_ct_path;
        $conf['cache_default_class']            = 'ConsistentCache';
        if (!is_readable('/data/conf/clstr.cnf')) {
          $conf['cache_class_cache_form']       = 'DrupalDatabaseCache';
          $conf['cache_class_cache_bootstrap']  = 'DrupalDatabaseCache';
        }
        $conf['consistent_cache_default_class'] = 'Redis_Cache';
        $conf['consistent_cache_default_safe']  = TRUE;
        $conf['consistent_cache_buffer_mechanism'] = 'ConsistentCacheBuffer';
        $conf['consistent_cache_default_strict'] = FALSE;
        $conf['consistent_cache_strict_cache_bootstrap'] = TRUE;
      }
      if (!is_readable('/data/conf/clstr.cnf')) {
        $conf['cache_class_cache_form']         = 'DrupalDatabaseCache';
        $conf['cache_class_cache_bootstrap']    = 'DrupalDatabaseCache';
      }
      $conf['redis_client_interface']           = 'PhpRedis';
      $conf['redis_client_host']                = '127.0.0.1';
      $conf['redis_client_port']                = '6379';
      $conf['redis_client_password']            = 'isfoobared';
      $conf['redis_client_base']                = '8';
      $conf['cache_prefix']                     = $this_prefix;
      $conf['page_cache_invoke_hooks']          = TRUE;  // D7 === Do not use Aggressive Mode
      $conf['page_cache_without_database']      = FALSE; // D7 === Do not use Aggressive Mode
      $conf['page_cache_maximum_age']           = 0;     // D7 === max-age in the Cache-Control header (ignored by Speed Booster)
      $conf['page_cache_max_age']               = 0;     // D6 === max-age in the Cache-Control header (ignored by Speed Booster)
      $conf['cache_lifetime']                   = 0;     // D7 === BOA uses Speed Booster / Nginx micro-caching instead
      $conf['page_cache_lifetime']              = 0;     // D6 === BOA uses Speed Booster / Nginx micro-caching instead
    }
    if ($all_ini['redis_exclude_bins'] && !is_readable('/data/conf/clstr.cnf')) {
      $excludes = array();
      $excludes = explode(",", $all_ini['redis_exclude_bins']);
      foreach ($excludes as $exclude) {
        $exclude = rtrim($exclude);
        $exclude = ltrim($exclude);
        if ($drupal_core >= 8) {
          $bin_exclude = $exclude;
          $settings['cache']['bins'][$bin_exclude] = 'cache.backend.database';
        }
        else {
          $bin_exclude = 'cache_class_' . $exclude;
          $conf[$bin_exclude] = 'DrupalDatabaseCache';
        }
        if ($is_dev && !$is_backend) {
          header("X-Ini-Redis-Exclude-Bin-" . $exclude . ": " . $bin_exclude);
        }
      }
    }
  }
}


