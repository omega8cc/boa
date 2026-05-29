<?php # global settings.php


/**
 * Core versions init
 */
$backdropcms   = FALSE;
$drupal_core   = FALSE;
$drupal_id     = FALSE;


/**
 * Vars init
 */
$custom_cache  = FALSE;
$custom_da     = FALSE;
$custom_fb     = FALSE;
$da_inc        = FALSE;
$deny_anon     = FALSE;
$hidden_uri    = FALSE;
$high_traffic  = FALSE;
$ini_loc_src   = FALSE;
$ini_plr_src   = FALSE;
$is_backend    = FALSE;
$is_bot        = FALSE;
$is_dev        = FALSE;
$is_install    = FALSE;
$is_tmp        = FALSE;
$local_req     = FALSE;
$no_dns        = FALSE;
$raw_host      = FALSE;
$redis_comprs  = FALSE;
$redis_lock    = FALSE;
$redis_path    = FALSE;
$site_subdir   = FALSE;
$use_auto_se   = FALSE;
$use_cache_ct  = FALSE;
$use_valkey    = FALSE;
$usr_loc_ini   = FALSE;
$usr_plr_ini   = FALSE;
$valkey_up     = FALSE;


/**
 * BOA INI defaults
 */
$boa_ini = array(
  'session_cookie_ttl' => '86400',
  'session_gc_eol' => '86400',
  'redis_use_modern' => TRUE,
  'redis_flush_forced_mode' => TRUE,
  'redis_lock_enable' => TRUE,
  'redis_path_enable' => TRUE,
  'redis_scan_enable' => FALSE,
  'redis_cache_disable' => FALSE,
  'redis_old_nine_mode' => FALSE,
  'redis_old_eight_mode' => FALSE,
  'sql_conversion_mode' => FALSE,
  'enable_strict_user_register_protection' => FALSE,
  'entitycache_dont_enable' => FALSE,
  'views_cache_bully_dont_enable' => FALSE,
  'views_content_cache_dont_enable' => FALSE,
  'autoslave_enable' => FALSE,
  'cache_consistent_enable' => FALSE,
  'redis_exclude_bins' => FALSE,
  'speed_booster_anon_cache_ttl' => FALSE,
  'allow_anon_node_add' => FALSE,
  'enable_newrelic_integration' => FALSE,
  'disable_admin_dos_protection' => FALSE,
  'ignore_user_register_protection' => FALSE,
  'allow_private_file_downloads' => FALSE,
  'server_name_cookie_domain' => FALSE,
  'auto_detect_facebook_integration' => TRUE,      // For backward compatibility until next release, then FALSE
  'auto_detect_domain_access_integration' => TRUE, // For backward compatibility until next release, then FALSE
  'advagg_auto_configuration' => FALSE,            // Will be set to TRUE in boa_site_control.ini if the module is enabled
  'disable_drupal_page_cache' => FALSE,            // FALSE for backward compatibility and max performance
  'set_composer_manager_vendor_dir' => FALSE,      // FALSE by default to not break site installation depending on custom value
  // --- Valkey/Redis probe tuning + cache observability (added 2026-05) -----
  // See global-if-valkey.inc / global-if-redis.inc and global-valkey.inc.
  // NOTE: BOA keeps a single, stable "redis_" namespace for ALL cache control
  // INI variables, even when the server runs Valkey (a drop-in Redis fork).
  'redis_connect_timeout' => '0.7',                // probe TCP connect timeout (s); was hardcoded 0.2
  'redis_read_timeout' => '0.7',                   // probe read timeout (s); was hardcoded 0.2
  'redis_backoff_ttl' => '15',                     // backoff window (s) after a failed probe; was hardcoded 60
  'redis_probe_retry' => TRUE,                     // retry the probe once before tripping the backoff flag
  'redis_flush_apcu_on_recovery' => TRUE,          // clear local APCu when the cache backend transitions down->up
  'redis_debug_header' => FALSE,                   // emit always-on, non-sensitive X-Cache-* state headers (enable per-site to investigate)
  'redis_debug' => FALSE,                          // arm the probe fallback log; only then is the *.debug.flag file checked (disk I/O)
);

