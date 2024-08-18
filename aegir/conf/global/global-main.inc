<?php # global settings.php


/**
 * Bots protection for all tmp/dev sites - works also for aliases
 */
if ($is_bot) {
  if ($is_tmp) {
    // Ignore known bots
    header('X-Accel-Expires: 300');
    header('HTTP/1.0 404 Not Found');
    header("Connection: close");
    exit;
  }
}


/**
 * Site cron protection - cron works only for live sites
 */
if (preg_match("/^\/cron\.php/", $_SERVER['REQUEST_URI']) ||
    preg_match("/^\/cron\//", $_SERVER['REQUEST_URI'])) {
  if ($is_tmp) {
    // Ignore cron requests
    header('X-Accel-Expires: 300');
    header('HTTP/1.0 404 Not Found');
    header("Connection: close");
    exit;
  }
}


/**
 * Fix for Akamai, CloudFlare and others running via Proxy
 */
if (isset($_SERVER['REMOTE_ADDR'])) {
  if (isset($_SERVER['HTTP_X_FORWARDED_FOR']) &&
      $_SERVER['HTTP_X_FORWARDED_FOR'] !== "127.0.0.1") {
    $_SERVER['REMOTE_ADDR'] = $_SERVER['HTTP_X_FORWARDED_FOR'];
  }
  if (isset($_SERVER['HTTP_X_REAL_IP']) &&
      $_SERVER['HTTP_X_REAL_IP'] !== "127.0.0.1") {
    $_SERVER['REMOTE_ADDR'] = $_SERVER['HTTP_X_REAL_IP'];
  }
  if (isset($_SERVER['HTTP_CF_CONNECTING_IP']) &&
      $_SERVER['HTTP_CF_CONNECTING_IP'] !== "127.0.0.1") {
    $_SERVER['REMOTE_ADDR'] = $_SERVER['HTTP_CF_CONNECTING_IP'];
  }
  if (isset($_SERVER['HTTP_TRUE_CLIENT_IP']) &&
      $_SERVER['HTTP_TRUE_CLIENT_IP'] !== "127.0.0.1") {
    $_SERVER['REMOTE_ADDR'] = $_SERVER['HTTP_TRUE_CLIENT_IP'];
  }
}


/**
 * The nodns protection
 */
if ($no_dns) {
  if ($local_req) {
    // Allow local requests
    if (!$is_backend && isset($_SERVER['REMOTE_ADDR'])) {
      header("X-Local-Y: " . $_SERVER['REMOTE_ADDR']);
    }
  }
  else {
    // Ignore remote requests
    header('X-Accel-Expires: 60');
    header('HTTP/1.0 404 Not Found');
    header("Connection: close");
    exit;
  }
}


/**
 * The hidden uri protection
 */
if ($hidden_uri) {
  if ($local_req) {
    // Allow local requests to hidden uri
    if (!$is_backend && isset($_SERVER['REMOTE_ADDR'])) {
      header("X-Local-URI-Y: " . $_SERVER['REMOTE_ADDR']);
    }
  }
  else {
    // Ignore remote requests
    header('X-Accel-Expires: 60');
    header('HTTP/1.0 404 Not Found');
    header("Connection: close");
    exit;
  }
}


/**
 * Use Aegir/BOA specific MAIN_SITE_NAME instead of possibly fake SERVER_NAME
 */
if (isset($_SERVER['MAIN_SITE_NAME'])) {
  $_SERVER['SERVER_NAME'] = $_SERVER['MAIN_SITE_NAME'];
}


/**
 * Set MAIN_SITE_NAME to match SERVER_NAME, if MAIN_SITE_NAME is not set
 */
if (!isset($_SERVER['MAIN_SITE_NAME']) && isset($_SERVER['SERVER_NAME'])) {
  $_SERVER['MAIN_SITE_NAME'] = $_SERVER['SERVER_NAME'];
}


/**
 * Required for proper Redis support on command line / via Drush
 */
if (isset($_SERVER['HTTP_HOST']) && !isset($_SERVER['SERVER_NAME'])) {
  $_SERVER['SERVER_NAME'] = $_SERVER['HTTP_HOST'];
}


/**
 * Force backward compatible SERVER_SOFTWARE
 */
if (!$is_backend) {
  if (isset($_SERVER['SERVER_SOFTWARE']) &&
      !preg_match("/ApacheSolarisNginx/i", $_SERVER['SERVER_SOFTWARE'])) {
    $_SERVER['SERVER_SOFTWARE'] = 'ApacheSolarisNginx/1.27.0';
  }
}


/**
 * Early bots redirect on protected URLs
 */
if (!$is_backend) {
  if (isset($_SERVER['HTTP_HOST']) && $is_bot) {
    if (preg_match("/(?:^tmp\.|\.test\.|\.tmp\.)/i", $_SERVER['HTTP_HOST'])) {
      // Deny known search bots on ^(tmp|foo.(tmp|test)).domain subdomains
      header('X-Accel-Expires: 60');
      header("HTTP/1.1 301 Moved Permanently");
      header("Location: http://www.aegirproject.org/");
      header("Connection: close");
      exit;
    }
    elseif (preg_match("/\.(?:host8|boa|aegir|o8)\.(?:biz|io|cc)$/i", $_SERVER['HTTP_HOST'])) {
      // Deny known search bots on some protected CI subdomains
      header('X-Accel-Expires: 60');
      header("HTTP/1.1 301 Moved Permanently");
      header("Location: https://omega8.cc/");
      header("Connection: close");
      exit;
    }
  }
}


/**
 * Disable reporting errors by default - enable later only for foo.dev.domain
 */
error_reporting(0);


/**
 * Hostmaster specific settings
 */
if ($conf['install_profile'] === 'hostmaster') {
  $conf['hosting_require_disable_before_delete'] = 0;
  $conf['hosting_task_refresh_timeout'] = 5555;
  $conf['theme_link'] = FALSE;
  $conf['cache'] = 0;
  if (!$is_backend && isset($_SERVER['HTTP_USER_AGENT'])) {
    ini_set('session.cookie_lifetime', 0); // Force log-out on browser quit
    header('X-Accel-Expires: 1');
    if (!file_exists('/data/conf/no-https-aegir.inc')) {
      $request_type = ($_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' ||
      $_SERVER['HTTPS'] === 'on') ? 'SSL' : 'NONSSL';
      if ($request_type !== "SSL" &&
          !preg_match("/^\/cron\.php/", $_SERVER['REQUEST_URI'])) { // we force secure connection here
        header('X-Accel-Expires: 5');
        header("HTTP/1.1 301 Moved Permanently");
        header("Location: https://" . $_SERVER['HTTP_HOST'] . $_SERVER['REQUEST_URI']);
        header("Connection: close");
        exit;
      }
    }
    if (isset($_SERVER['HTTP_HOST']) &&
        preg_match("/\.(?:host8|boa|aegir|o8)\.(?:biz|io|cc)$/i", $_SERVER['HTTP_HOST'])) {
      if (preg_match("/^\/admin\/user\/user\/create/", $_SERVER['REQUEST_URI']) ||
          preg_match("/^\/node\/add\/server/", $_SERVER['REQUEST_URI']) ||
          preg_match("/^\/node\/(?:1|2|4|5|7|8|10)\/(?:edit|delete)/", $_SERVER['REQUEST_URI'])) {
        header('X-Accel-Expires: 5');
        header("HTTP/1.1 301 Moved Permanently");
        header("Location: https://" . $_SERVER['HTTP_HOST'] . "/hosting/sites");
        header("Connection: close");
        exit;
      }
    }
  }
}


/**
 * Optional site and platform level settings defined in the ini files
 * Note: the site-level ini file takes precedence over platform level ini
 */
$all_ini = $boa_ini;
if (is_readable('sites/all/modules/boa_platform_control.ini')) {
  $ini_plr_src = 'sites/all/modules/boa_platform_control.ini';
}
if ($ini_plr_src) {
  $usr_plr_ini = array();
  $usr_plr_ini = parse_ini_file($ini_plr_src);
}
if (is_readable('sites/' . $_SERVER['SERVER_NAME'] . '/modules/boa_site_control.ini')) {
  $ini_loc_src = 'sites/' . $_SERVER['SERVER_NAME'] . '/modules/boa_site_control.ini';
}
if ($ini_loc_src) {
  $usr_loc_ini = array();
  $usr_loc_ini = parse_ini_file($ini_loc_src);
}
if (is_array($usr_plr_ini) && $usr_plr_ini) {
  $all_ini = array_merge($all_ini, $usr_plr_ini);
}
if (is_array($usr_loc_ini) && $usr_loc_ini) {
  $all_ini = array_merge($all_ini, $usr_loc_ini);
}


/**
 * Display All Active INI Values on .dev. URL
 */
if (is_array($all_ini) && $is_dev && !$is_backend) {
  if ($ini_plr_src) {
    header("X-Ini-Plr-Src: " . $ini_plr_src);
  }
  if ($ini_loc_src) {
    header("X-Ini-Loc-Src: " . $ini_loc_src);
  }
  if (!$ini_plr_src && !$ini_loc_src) {
    header("X-Ini-Src: BOA-Default");
  }
  header("X-Ini-Redis-Use-Modern: " . $all_ini['redis_use_modern']);
  header("X-Ini-Redis-Flush-Forced-Mode: " . $all_ini['redis_flush_forced_mode']);
  header("X-Ini-Redis-Lock-Enable: " . $all_ini['redis_lock_enable']);
  header("X-Ini-Redis-Path-Enable: " . $all_ini['redis_path_enable']);
  header("X-Ini-Redis-Scan-Enable: " . $all_ini['redis_scan_enable']);
  header("X-Ini-Redis-Old-Nine-Mode: " . $all_ini['redis_old_nine_mode']);
  header("X-Ini-Redis-Old-Eight-Mode: " . $all_ini['redis_old_eight_mode']);
  header("X-Ini-Redis-Cache-Disable: " . $all_ini['redis_cache_disable']);
  header("X-Ini-Redis-Exclude-Bins: " . $all_ini['redis_exclude_bins']);
  header("X-Ini-Speed-Booster-Anon-Cache-Ttl: " . $all_ini['speed_booster_anon_cache_ttl']);
  header("X-Ini-Allow-Anon-Node-Add: " . $all_ini['allow_anon_node_add']);
  header("X-Ini-Enable-NewRelic-Integration: " . $all_ini['enable_newrelic_integration']);
  header("X-Ini-Disable-Admin-Dos-Protection: " . $all_ini['disable_admin_dos_protection']);
  header("X-Ini-Allow-Private-File-Downloads: " . $all_ini['allow_private_file_downloads']);
  header("X-Ini-Server-Name-Cookie-Domain: " . $all_ini['server_name_cookie_domain']);
  header("X-Ini-Auto-Detect-Facebook-Integration: " . $all_ini['auto_detect_facebook_integration']);
  header("X-Ini-Auto-Detect-Domain-Access-Integration: " . $all_ini['auto_detect_domain_access_integration']);
  header("X-Ini-Advagg-Auto-Configuration: " . $all_ini['advagg_auto_configuration']);
  header("X-Ini-Sql-Conversion-Mode: " . $all_ini['sql_conversion_mode']);
  header("X-Ini-Enable-Strict-User-Register-Protection: " . $all_ini['enable_strict_user_register_protection']);
  header("X-Ini-Entitycache-Dont-Enable: " . $all_ini['entitycache_dont_enable']);
  header("X-Ini-Views-Cache-Bully-Dont-Enable: " . $all_ini['views_cache_bully_dont_enable']);
  header("X-Ini-Views-Content-Cache-Dont-Enable: " . $all_ini['views_content_cache_dont_enable']);
  header("X-Ini-Ignore-User-Register-Protection: " . $all_ini['ignore_user_register_protection']);
  header("X-Ini-Session-Cookie-Ttl: " . $all_ini['session_cookie_ttl']);
  header("X-Ini-Session-Gc-Eol: " . $all_ini['session_gc_eol']);
  header("X-Ini-Disable-Drupal-Page-Cache: " . $all_ini['disable_drupal_page_cache']);
  header("X-Ini-Set-Composer-Manager-Vendor-Dir: " . $all_ini['set_composer_manager_vendor_dir']);
  header("X-Ini-AutoSlave-Enable: " . $all_ini['autoslave_enable']);
  header("X-Ini-CacheConsistent-Enable: " . $all_ini['cache_consistent_enable']);
}


