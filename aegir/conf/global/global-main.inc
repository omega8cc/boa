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
  if (($is_tmp) || (file_exists('/data/conf/sites-cron-off.ctrl'))) {
    // Ignore cron requests
    header('X-Accel-Expires: 300');
    header('HTTP/1.0 404 Not Found');
    header("Connection: close");
    exit;
  }
}


/**
 * Support real IP detection behind proxies (Cloudflare, Akamai, etc.)
 */
if (isset($_SERVER['REMOTE_ADDR']) && php_sapi_name() !== 'cli') {

  $real_ip = null;
  $proxy_header = null;
  $proxy_ip = null;

  // Handle possible comma-separated proxy chain in REMOTE_ADDR
  $raw_proxy_ip = $_SERVER['REMOTE_ADDR'];
  $proxy_ip_list = array_map('trim', explode(',', $raw_proxy_ip));
  $proxy_ip_list = array_filter($proxy_ip_list, function ($ip) {
    return filter_var($ip, FILTER_VALIDATE_IP);
  });

  if (!empty($proxy_ip_list)) {
    $proxy_ip = end($proxy_ip_list); // Trust the last proxy in the chain
  }

  // Detect real client IP using known proxy headers
  if (!empty($_SERVER['HTTP_CF_CONNECTING_IP'])) {
    // Cloudflare (single IP, trusted)
    $real_ip = trim($_SERVER['HTTP_CF_CONNECTING_IP']);
    $proxy_header = 'CF-Connecting-IP';
  }
  elseif (!empty($_SERVER['HTTP_TRUE_CLIENT_IP'])) {
    // Akamai / Fastly (single IP)
    $real_ip = trim($_SERVER['HTTP_TRUE_CLIENT_IP']);
    $proxy_header = 'True-Client-IP';
  }
  elseif (!empty($_SERVER['HTTP_X_REAL_IP'])) {
    // NGINX-style (single IP)
    $real_ip = trim($_SERVER['HTTP_X_REAL_IP']);
    $proxy_header = 'X-Real-IP';
  }
  elseif (!empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
    // Generic proxy chain (may contain multiple IPs)
    $forwarded_ips = array_map('trim', explode(',', $_SERVER['HTTP_X_FORWARDED_FOR']));
    $forwarded_ips = array_filter($forwarded_ips, function ($ip) {
      return filter_var($ip, FILTER_VALIDATE_IP);
    });
    if (!empty($forwarded_ips)) {
      $real_ip = $forwarded_ips[0]; // First = original client IP
      $proxy_header = 'X-Forwarded-For';
    }
  }

  // Apply the final values
  if (!empty($real_ip) && !empty($proxy_ip) && !empty($proxy_header)) {
    $_SERVER['REMOTE_ADDR'] = $real_ip;

    if (isset($drupal_core) && $drupal_core >= 8) {
      $settings['reverse_proxy'] = TRUE;
      $settings['reverse_proxy_header'] = $proxy_header;
      $settings['reverse_proxy_addresses'] = array($proxy_ip);
    }
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
 * Required for proper Valkey/Redis support on command line / via Drush
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
    $_SERVER['SERVER_SOFTWARE'] = 'ApacheSolarisNginx/1.29.3';
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
      header("Location: http://www.aegirproject.org/", true, 301);
      exit;
    }
    elseif (preg_match("/\.(?:host8|boa|aegir|o8)\.(?:biz|io|cc)$/i", $_SERVER['HTTP_HOST'])) {
      // Deny known search bots on some protected CI subdomains
      header('X-Accel-Expires: 60');
      header("Location: https://omega8.cc/", true, 301);
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
if ($conf['install_profile'] == 'hostmaster') {
  $conf['hosting_require_disable_before_delete'] = 0;
  $conf['hosting_task_refresh_timeout'] = 5555;
  $conf['theme_link'] = FALSE;
  $conf['cache'] = 0;
  if (!$is_backend && isset($_SERVER['HTTP_USER_AGENT'])) {
    $conf['environment_indicator_overwrite'] = TRUE;
    $conf['environment_indicator_overwritten_position'] = 'top';
    if (is_readable('/data/conf/development-env.ctrl')) {
      $conf['environment_indicator_overwritten_name'] = 'Development';
      $conf['environment_indicator_overwritten_color'] = '#00AA00'; // Green
    }
    elseif (is_readable('/data/conf/staging-env.ctrl')) {
      $conf['environment_indicator_overwritten_name'] = 'Staging';
      $conf['environment_indicator_overwritten_color'] = '#FFCC00'; // Yellow
    }
    elseif (is_readable('/data/conf/production-env.ctrl')) {
      $conf['environment_indicator_overwritten_name'] = 'Production';
      $conf['environment_indicator_overwritten_color'] = '#CC0000'; // Red
    }
    elseif (is_readable('/data/conf/testing-env.ctrl')) {
      $conf['environment_indicator_overwritten_name'] = 'Testing';
      $conf['environment_indicator_overwritten_color'] = '#FF69B4'; // Hot Pink
      //$conf['environment_indicator_overwritten_color'] = '#FFC0CB'; // Light Pink
    }
    else {
      $conf['environment_indicator_overwritten_name'] = 'Production';
      $conf['environment_indicator_overwritten_color'] = '#CC0000'; // Red
    }
    ini_set('session.cookie_lifetime', 0); // Force log-out on browser quit
    header('X-Accel-Expires: 1');
    if (!file_exists('/data/conf/no-https-aegir.inc')) {
      $request_type = ($_SERVER['HTTP_X_FORWARDED_PROTO'] == 'https' ||
      $_SERVER['HTTPS'] == 'on') ? 'SSL' : 'NONSSL';
      if ($request_type != "SSL" &&
          !preg_match("/^\/cron\.php/", $_SERVER['REQUEST_URI'])) { // we force secure connection here
        header('X-Accel-Expires: 5');
        header("Location: https://" . $_SERVER['HTTP_HOST'] . $_SERVER['REQUEST_URI'], true, 301);
        exit;
      }
    }
    if (isset($_SERVER['HTTP_HOST']) &&
        preg_match("/\.(?:host8|boa|aegir|o8)\.(?:biz|io|cc)$/i", $_SERVER['HTTP_HOST'])) {
      if (preg_match("/^\/admin\/user\/user\/create/", $_SERVER['REQUEST_URI']) ||
          preg_match("/^\/node\/add\/server/", $_SERVER['REQUEST_URI']) ||
          preg_match("/^\/node\/(?:1|2|4|5|7|8|10)\/(?:edit|delete)/", $_SERVER['REQUEST_URI'])) {
        header('X-Accel-Expires: 5');
        header("Location: https://" . $_SERVER['HTTP_HOST'] . "/hosting/sites", true, 301);
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
  header("X-Ini-Valkey-Use-Modern: " . $all_ini['redis_use_modern']);
  header("X-Ini-Valkey-Flush-Forced-Mode: " . $all_ini['redis_flush_forced_mode']);
  header("X-Ini-Valkey-Lock-Enable: " . $all_ini['redis_lock_enable']);
  header("X-Ini-Valkey-Path-Enable: " . $all_ini['redis_path_enable']);
  header("X-Ini-Valkey-Scan-Enable: " . $all_ini['redis_scan_enable']);
  header("X-Ini-Valkey-Old-Nine-Mode: " . $all_ini['redis_old_nine_mode']);
  header("X-Ini-Valkey-Old-Eight-Mode: " . $all_ini['redis_old_eight_mode']);
  header("X-Ini-Valkey-Cache-Disable: " . $all_ini['redis_cache_disable']);
  header("X-Ini-Valkey-Exclude-Bins: " . $all_ini['redis_exclude_bins']);
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
