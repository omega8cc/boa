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
 * Detecting subdirectory mode
 */
if (isset($_SERVER['SITE_SUBDIR'])) {
  $site_subdir = $_SERVER['SITE_SUBDIR'];
}
if (isset($_SERVER['RAW_HOST'])) {
  $raw_host = $_SERVER['RAW_HOST'];
}


/**
 * Backend and task detection
 */
if (function_exists('drush_get_command')) {
  $command = drush_get_command();
  if (isset($command['command'])) {
    $command = explode(" ", $command['command']);
    if (isset($command[0])) {
      if (!preg_match("/^help/", $command[0])) {
        $is_backend = TRUE;
      }
      if (preg_match("/^(provision-install|provision-save|provision-backup|php-eval)/", $command[0])) {
        if (!is_readable('/data/conf/clstr.cnf')) {
          $is_install = TRUE;
        }
      }
    }
  }
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
 * Bots detection
 */
if (isset($_SERVER['HTTP_USER_AGENT']) &&
    preg_match("/(?:crawl|bot|spider|tracker|click|parser|google|yahoo|yandex|baidu|bing)/i", $_SERVER['HTTP_USER_AGENT'])) {
  $is_bot = TRUE;
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
 * Site mode detection - works also for aliases
 */
if (isset($_SERVER['HTTP_HOST']) &&
    (preg_match("/(?:^dev\.|\.dev\.)/i", $_SERVER['HTTP_HOST']) ||
     preg_match("/(?:^devel\.|\.devel\.)/i", $_SERVER['HTTP_HOST']) ||
     preg_match("/(?:^tmp\.|\.tmp\.)/i", $_SERVER['HTTP_HOST']) ||
     preg_match("/(?:^temp\.|\.temp\.)/i", $_SERVER['HTTP_HOST']) ||
     preg_match("/(?:^temporary\.|\.temporary\.)/i", $_SERVER['HTTP_HOST']) ||
     preg_match("/(?:^test\.|\.test\.)/i", $_SERVER['HTTP_HOST']) ||
     preg_match("/(?:^testing\.|\.testing\.)/i", $_SERVER['HTTP_HOST']))) {
  $is_tmp = TRUE;
}


/**
 * Dev mode detection - works only for aliases
 */
if (isset($_SERVER['HTTP_HOST']) &&
    isset($_SERVER['MAIN_SITE_NAME']) &&
    preg_match("/(?:^dev\.|^devel\.|\.dev\.|\.devel\.)/i", $_SERVER['HTTP_HOST']) &&
    $_SERVER['HTTP_HOST'] != $_SERVER['MAIN_SITE_NAME'] &&
    $_SERVER['HTTP_HOST'] != $_SERVER['SERVER_NAME'] &&
    !$is_backend) {
  $is_dev = TRUE;
}


/**
 * Core version detection
 */
if (file_exists('web.config') || file_exists('index.php')) { // Check for the main entry point file
  if (file_exists('core')) {
    if (file_exists('vendor/symfony') ||
      file_exists('core/vendor/symfony') ||
      file_exists('autoload.php')) {
      $drupal_core = '8';
      $drupal_id = 'DVIII';
      if (file_exists('core/themes/olivero') && file_exists('core/themes/classy')) {
        $drupal_core = '9';
        $drupal_id = 'DIX';
      }
      if (file_exists('core/themes/olivero') && !file_exists('core/themes/classy')) {
        $drupal_core = '10';
        $drupal_id = 'DX';
      }
      if (file_exists('core/modules/workspaces_ui') && !file_exists('web.config')) {
        $drupal_core = '11';
        $drupal_id = 'DXI';
      }
      $use_valkey = TRUE;
    }
    else {
      $backdropcms = TRUE;
      $drupal_id = 'ND';
    }
  }
  elseif (file_exists('modules/path_alias_cache')) {
    $drupal_core = '6';
    $drupal_id = 'DVI';
    $use_valkey = TRUE;
  }
  else {
    $drupal_core = '7';
    $drupal_id = 'DVII';
    $use_valkey = TRUE;
  }
  if ($drupal_id && $is_dev && !$is_backend) {
    header('X-Backend: ' . $drupal_id);
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
 * The nodns mode detection
 */
if (isset($_SERVER['HTTP_HOST']) &&
    (preg_match("/(?:^nodns\.|\.nodns\.)/i", $_SERVER['HTTP_HOST']))) {
  $no_dns = TRUE;
}


/**
 * Local nodns request detection
 */
if (isset($_SERVER['REMOTE_ADDR']) &&
    (preg_match("/(^127\.0\.0\.1)$/i", $_SERVER['REMOTE_ADDR']) ||
     preg_match("/(^127\.0\.0\.1\, 127\.0\.0\.1)$/i", $_SERVER['REMOTE_ADDR']))) {
  $local_req = TRUE;
}


/**
 * Local path request check
 */
if (preg_match("/\/api\/hidden\//", $_SERVER['REQUEST_URI'])) {
  $hidden_uri = TRUE;
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
 * Required for proper Valkey support on command line / via Drush
 */
if (isset($_SERVER['HTTP_HOST']) && !isset($_SERVER['SERVER_NAME'])) {
  $_SERVER['SERVER_NAME'] = $_SERVER['HTTP_HOST'];
}


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
);


/**
 * Optional system level early overrides
 */
if (is_readable('/data/conf/settings.global.inc')) {
  require_once "/data/conf/settings.global.inc";
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


/**
 * Disable reporting errors by default - enable later only for foo.dev.domain
 */
error_reporting(0);


/**
 * Forced default settings
 */
if ($drupal_core >= 8) {
  //
  // Drupal 8 behaviour is confusing, because while it is possible
  // to force settings listed below, they will not be shown in the
  // site admin area. For example, CSS/JS aggregation checkboxes
  // will accept on/off changes on form submit, while being silently
  // overridden here.
  //
  $config['image.settings']['allow_insecure_derivatives'] = TRUE;  // Not sure if it's a good idea in D8
  $config['image.settings']['suppress_itok_output'] = TRUE;        // Not sure if it's a good idea in D8
  $config['system.cron']['threshold.autorun'] = FALSE;             // Disable poormanscron (legacy)
  $config['system.cron']['threshold']['auto'] = 0;                 // Disable auto-cron (current)
  $config['system.logging']['error_level'] = 'hide';               // Disable errors on screen
  $config['system.performance']['css']['preprocess'] = TRUE;       // Enable hardcoded CSS aggregation
  $config['system.performance']['js']['preprocess'] = TRUE;        // Enable hardcoded JS aggregation
  $config['system.performance']['response.gzip'] = FALSE;          // Nginx already compresses everything
  //$config['system.file']['default_scheme'] = 'public';             // Force public downloads by default
}
else {
  if ($backdropcms) {
    $conf['css_gzip_compression'] = FALSE; // Nginx already compresses everything
    $conf['js_gzip_compression'] = FALSE;  // Nginx already compresses everything
    $settings['backdrop_drupal_compatibility'] = TRUE; // Enable Drupal backwards compatibility
  }
  $conf['page_compression'] = 0;    // Nginx already compresses everything
  $conf['boost_crawl_on_cron'] = 0; // Deny Boost crawler
  $conf['cron_safe_threshold'] = 0; // Disable poormanscron
  $conf['preprocess_css'] = 1;      // Enable hardcoded CSS aggregation
  $conf['preprocess_js'] = 1;       // Enable hardcoded JS aggregation
  $conf['file_downloads'] = 1;      // Force public downloads by default in D6
  $conf['file_default_scheme'] = 'public'; // Force public downloads by default in D7
  $conf['error_level'] = 0;         // Disable errors on screen
  $conf['statistics_enable_access_log'] = 0;   // Disable access log stats
  $conf['allow_authorize_operations'] = FALSE; // Disable insecure plugin manager
  $conf['admin_menu_cache_client'] = FALSE;    // Disable caching in admin_menu #442560
  $conf['boost_ignore_htaccess_warning'] = 1;  // Silence false alarm in boost
  $conf['expire_flush_front'] = 1;             // Default settings for expire module
  $conf['expire_flush_node_terms'] = 1;        // Default settings for expire module
  $conf['expire_flush_menu_items'] = 0;        // Default settings for expire module
  $conf['expire_flush_cck_references'] = 0;    // Default settings for expire module
  $conf['expire_include_base_url'] = 1;        // Default settings for expire module
  $conf['js_server_software'] = "other";       // Set JS Callback handler server software
  $conf['video_ffmpeg_instances'] = 1;         // Force safe default for ffmpeg
  $conf['securepages_enable'] = 1;             // Force to avoid issues with ssl proxy
  $conf['less_devel'] = FALSE;                 // Prevent CSS regeneration on every page load
  $conf['drupal_http_request_fails'] = FALSE;  // Avoid false alarm
  $conf['image_allow_insecure_derivatives'] = TRUE; // Enable to avoid known issues: https://drupal.org/drupal-7.20-release-notes
  $conf['theme_cloudy_settings']['omega_rebuild_aggregates'] = FALSE;     // Do not allow to turn it on by default
  $conf['theme_cloudy_settings']['omega_rebuild_theme_registry'] = FALSE; // Do not allow to turn it on by default
  $update_free_access = FALSE;
  $conf['webform_table'] = TRUE; // Workaround for SA-CONTRIB-2015-063 https://www.drupal.org/node/2445935
  $conf['features_rebuild_on_flush'] = FALSE; // https://michaelshadle.com/2015/04/21/speeding-up-drupal-cache-flushing
  $conf['entity_rebuild_on_flush'] = FALSE; // http://a-fro.com/speed-up-cache-clearing-on-drupal7
  $conf['redis_eval_enabled'] = TRUE;
  // Use EVAL commands to greatly speed up cache clearing
  // Enable when https://www.drupal.org/node/2487333 is fixed
}


/**
 * Logic for the front-end only
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

  if ($is_dev) {
    // Dev mode switch
    error_reporting(E_ALL & ~E_NOTICE);
    ini_set('display_errors', TRUE);
    ini_set('display_startup_errors', TRUE);
    ini_set('opcache.revalidate_freq', '0');
    if (!$is_backend) {
      header("X-Opcache-Revalidate-Freq: 0");
    }
    if ($drupal_core >= 8) {
      unset($config['system.logging']['error_level']);            // Stop hardcoding no errors on screen
      unset($config['system.performance']['cache.page.max_age']); // Stop hardcoding internal page cache
      unset($config['system.performance']['css']['preprocess']);  // Stop hardcoding CSS aggregation
      unset($config['system.performance']['js']['preprocess']);   // Stop hardcoding JS aggregation
      if (is_readable('sites/' . $_SERVER['SERVER_NAME'] . '/files/development.services.yml')) {
        //
        // This file, if exists, disables Valkey on the fly!
        //
        $settings['container_yamls'][] = 'sites/' . $_SERVER['SERVER_NAME'] . '/files/development.services.yml';
        //
        // The two settings below make sense only if the development.services.yml file
        // located in the sites/domain/files/ dir contains at least these three lines:
        //
        // services:
        //   cache.backend.null:
        //     class: Drupal\Core\Cache\NullBackendFactory
        //
        $settings['cache']['bins']['render'] = 'cache.backend.null';
        $settings['cache']['bins']['dynamic_page_cache'] = 'cache.backend.null';
        //
        // Warning: you must clear caches via Aegir interface or with Drush
        // before these lines will start working on .dev. alias without error 500
        // saying: You have requested a non-existent service "cache.backend.null"
        //
        // To enable Twig debugging add in the development.services.yml file also lines:
        //
        // parameters:
        //   twig.config:
        //     debug: true
        //     auto_reload: true
        //     cache: true
        //
        // Note that normally you should not disable Twig cache, since auto_reload
        // is enough for development and debugging, withot slowing down everything;
        // see also: https://www.drupal.org/node/1903374
        //
      }
    }
    else {
      $conf['xmlsitemap_submit'] = 0; // Disable XML Sitemap for foo.dev.domain
      $conf['xmlsitemap_update'] = 0; // Disable XML Sitemap for foo.dev.domain
      unset($conf['cache']);          // Stop hardcoding internal page cache
      unset($conf['error_level']);    // Stop hardcoding no errors on screen
      unset($conf['less_devel']);     // Stop hardcoding CSS regeneration on every page load
      unset($conf['preprocess_css']); // Stop hardcoding CSS aggregation
      unset($conf['preprocess_js']);  // Stop hardcoding JS aggregation
      unset($conf['theme_cloudy_settings']['omega_rebuild_aggregates']);     // Do not force on dev URLs
      unset($conf['theme_cloudy_settings']['omega_rebuild_theme_registry']); // Do not force on dev URLs
    }
  }
  else {
    if (preg_match("/^\/civicrm/", $_SERVER['REQUEST_URI'])) {
      // Force custom opcache TTL for CiviCRM codebase
      ini_set('opcache.revalidate_freq', '180');
      if (!$is_backend) {
        header("X-Opcache-Revalidate-Freq: 180");
      }
    }
    else {
      // Set sane default opcache TTL on non-dev sites
      ini_set('opcache.revalidate_freq', '60');
      if (!$is_backend) {
        header("X-Opcache-Revalidate-Freq: 60");
      }
    }
  }
}


/**
 * Enable page caching if disable_drupal_page_cache is not set to TRUE,
 * but only on non-dev URLs and only for the front-end.
 */
if (!$is_backend && !$is_dev) {
  if (!$is_bot && $all_ini['disable_drupal_page_cache']) {
    if ($drupal_core >= 8) {
      $config['system.performance']['cache.page.max_age'] = 0;
    }
    else {
      $conf['cache'] = 0;
    }
  }
  else {
    if ($drupal_core >= 8) {
      $config['system.performance']['cache.page.max_age'] = 60;
    }
    else {
      $conf['cache'] = 1;
    }
  }
}


/**
 * Disable page caching when Speed Booster is disabled on the fly
 */
if (!$is_bot && isset($_SERVER['REQUEST_URI']) &&
    preg_match("/nocache=1/", $_SERVER['REQUEST_URI'])) {
  if ($drupal_core >= 8) {
    $config['system.performance']['cache.page.max_age'] = 0;
  }
  else {
    $conf['cache'] = 0;
  }
}


/**
 * Session Cookie TTL settings
 *
 * Set session cookie lifetime (in seconds), i.e. the time from the session is
 * created to the cookie expires, i.e. when the browser is expected to discard
 * the cookie. The value 0 means "until the browser is closed".
 */
ini_set('session.cookie_lifetime', $all_ini['session_cookie_ttl']);


/**
 * Session Garbage Collector EOL settings
 *
 * Set session lifetime (in seconds), i.e. the time from the user's last visit
 * to the active session may be deleted by the session garbage collector. When
 * a session is deleted, authenticated users are logged out, and the contents
 * of the user's $_SESSION variable is discarded.
 */
ini_set('session.gc_maxlifetime', $all_ini['session_gc_eol']);


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
  else {
    $use_valkey = TRUE;
  }
}


/**
 * Main section starts here
 */
if (isset($_SERVER['SERVER_NAME']) &&
    $all_ini['allow_private_file_downloads']) {
  unset($conf['file_downloads']); // Disable hardcoded public downloads for D6
  unset($conf['file_default_scheme']); // Disable hardcoded public downloads for D7
  //unset($config['system.file']['default_scheme']); // Disable hardcoded public downloads for D8+
  if ($is_dev && !$is_backend) {
    header('X-Is-Cart: YES');
  }
}

/* ---------------- Feature switch -------------------------------------- */
if ($drupal_core >= 6) {
  $use_valkey = TRUE;
}

if (isset($_SERVER['SERVER_NAME'])) {
  if ($all_ini['valkey_cache_disable'] || $all_ini['redis_cache_disable']) {
    $use_valkey = FALSE;
  }
}

if (!$is_bot && isset($_SERVER['REQUEST_URI'])) {
  if (preg_match("/noredis=1/", $_SERVER['REQUEST_URI'])) {
    $use_valkey = FALSE;
  }
}

/* ---------------- Defaults -------------------------------------------- */
$valkey_up = FALSE;

/* ---------------- Connection targets ---------------------------------- */
$valkey_socket_path = '/run/valkey/valkey.sock';
$valkey_host        = '127.0.0.1';
$valkey_port        = 6379;
$valkey_pass_file   = '/data/conf/valkey/pass.inc';

/* ---------------- Timeouts & backoff ---------------------------------- */
$connect_timeout_s  = 0.2;   // short and non-blocking feel
$read_timeout_s     = 0.2;   // keep calls snappy
$backoff_ttl_s      = 60;    // do not retry within this window after a failure
$flag_dir_run       = '/var/tmp/fpm';
$flag_file_fallback = '/data/conf/arch/valkey.disabled.flag'; // fallback

/* ---------------- Optional debug log ---------------------------------- */
// Set to an absolute path to enable lightweight probe logging.
// Example: '/var/tmp/fpm/valkey-fallback.log'
$redis_debug_log    = '';

/* ---------------- Helpers (filesystem only) ---------------------------- */
function _valkey_backoff_flag_path($flag_dir_run, $fallback) {
  $path = $fallback;
  if (is_dir($flag_dir_run)) {
    if (is_writable($flag_dir_run)) {
      $path = rtrim($flag_dir_run, '/').'/valkey.disabled.flag';
    }
  }
  return $path;
}

function _valkey_backoff_is_active($flag_path, $ttl) {
  $active = FALSE;
  if (is_file($flag_path)) {
    $age = time() - @filemtime($flag_path);
    if ($age >= 0 && $age < $ttl) {
      $active = TRUE;
    }
  }
  return $active;
}

function _valkey_backoff_touch($flag_path) {
  @touch($flag_path);
}

function _valkey_backoff_clear($flag_path) {
  if (is_file($flag_path)) {
    @unlink($flag_path);
  }
}

function _valkey_dbg_write($log_path, $line) {
  if (!empty($log_path)) {
    $msg = date('c').' '.$line."\n";
    @file_put_contents($log_path, $msg, FILE_APPEND);
  }
}

/* ------------------- Probe Valkey once with guard --------------------- */
$flag_path = _valkey_backoff_flag_path($flag_dir_run, $flag_file_fallback);
$skip_probe = _valkey_backoff_is_active($flag_path, $backoff_ttl_s);

if ($use_valkey) {
  if (!$skip_probe) {
    if (class_exists('Redis')) {
      $r = new Redis();
      $connected = FALSE;
      $last_reason = 'init';

      // Try socket first.
      if (!empty($valkey_socket_path) && @is_readable($valkey_socket_path)) {
        try {
          $connected = $r->connect($valkey_socket_path);
        } catch (Exception $e) {
          $connected = FALSE;
          $last_reason = 'connect-socket-exception';
        }
      }

      // Fallback to TCP.
      if (!$connected) {
        try {
          $connected = $r->connect($valkey_host, $valkey_port, $connect_timeout_s);
        } catch (Exception $e) {
          $connected = FALSE;
          $last_reason = 'connect-tcp-exception';
        }
      }

      if ($connected) {
        if (defined('Redis::OPT_READ_TIMEOUT')) {
          $r->setOption(Redis::OPT_READ_TIMEOUT, $read_timeout_s);
        }

        // Authenticate if password file exists.
        $auth_pass = 'isfoobared';
        if (is_file($valkey_pass_file)) {
          $auth_pass = trim((string) @file_get_contents($valkey_pass_file));
        }
        if ($auth_pass !== '') {
          try {
            if (!$r->auth($auth_pass)) {
              $connected = FALSE;
              $last_reason = 'auth-failed';
            }
          } catch (Exception $e) {
            $connected = FALSE;
            $last_reason = 'auth-exception';
          }
        }

        // Verify ping.
        if ($connected) {
          try {
            $pong = $r->ping();
            if ((is_string($pong) && stripos($pong, 'PONG') !== FALSE) || $pong === TRUE) {
              $valkey_up = TRUE;
            } else {
              $valkey_up = FALSE;
              $last_reason = 'ping-not-ok';
            }
          } catch (Exception $e) {
            $valkey_up = FALSE;
            $last_reason = 'ping-exception';
          }
        }

        if ($valkey_up) {
          _valkey_backoff_clear($flag_path);
          _valkey_dbg_write($redis_debug_log, 'VALKEY UP action=clear flag='.$flag_path.' reason=ok');
        } else {
          _valkey_backoff_touch($flag_path);
          _valkey_dbg_write($redis_debug_log, 'VALKEY DOWN action=touch flag='.$flag_path.' reason='.(string) $last_reason);
        }

        try {
          $r->close();
        } catch (Exception $e) {
          // ignore
        }
      } else {
        _valkey_backoff_touch($flag_path);
        _valkey_dbg_write($redis_debug_log, 'VALKEY DOWN action=touch flag='.$flag_path.' reason='.(string) $last_reason);
      }
    } else {
      // phpredis extension not available.
      $valkey_up = FALSE;
      _valkey_backoff_touch($flag_path);
      _valkey_dbg_write($redis_debug_log, 'VALKEY DOWN action=touch flag='.$flag_path.' reason=no-phpredis');
    }
  } else {
    $valkey_up = FALSE;
    _valkey_dbg_write($redis_debug_log, 'VALKEY SKIP reason=backoff-active flag='.$flag_path);
  }
}

/* ---------------- Diagnostics & final guard ---------------------------- */
if (!empty($is_dev)) {
  if (empty($is_backend)) {
    if ($use_valkey && $valkey_up) {
      header('X-Allow-Valkey: YES');
    } else {
      header('X-Allow-Valkey: NO');
    }
  }
}

if (!empty($is_install)) {
  $use_valkey = FALSE;
}

if ($all_ini['auto_detect_domain_access_integration']) {
  if (is_readable('sites/all/modules/domain/settings.inc')) {
    $da_inc = 'sites/all/modules/domain/settings.inc';
  }
  elseif (is_readable('sites/all/modules/contrib/domain/settings.inc')) {
    $da_inc = 'sites/all/modules/contrib/domain/settings.inc';
  }
  elseif (is_readable('profiles/' . $conf['install_profile'] . '/modules/domain/settings.inc')) {
    $da_inc = 'profiles/' . $conf['install_profile'] . '/modules/domain/settings.inc';
  }
  elseif (is_readable('profiles/' . $conf['install_profile'] . '/modules/contrib/domain/settings.inc')) {
    $da_inc = 'profiles/' . $conf['install_profile'] . '/modules/contrib/domain/settings.inc';
  }
}

/**
 * Activate mail_safety for sites-cron-off on the fly
 */
if (is_readable('/data/conf/sites-cron-off.ctrl')) {
  if ($drupal_core >= 8) {
    $config['automated_cron.settings']['interval'] = 0;
    $config['mail_safety.settings']['default_mail_address'] = '';
    $config['mail_safety.settings']['enabled'] = TRUE;
    $config['mail_safety.settings']['send_mail_to_dashboard'] = TRUE;
    $config['mail_safety.settings']['send_mail_to_default_mail'] = FALSE;
    $config['scheduler.settings']['lightweight_cron_access_key'] = '';
    $config['simple_cron.settings']['interval'] = 0;
    $config['system.cron']['key'] = '';
    $config['system.cron']['last'] = 0;
    $config['system.cron']['threshold']['auto'] = 0;
    $config['ultimate_cron.job.cron_queue']['status'] = FALSE;
    $config['ultimate_cron.settings']['scheduler'] = 'never';
  }
  else {
    $conf['mail_safety_enabled'] = TRUE;
    $conf['mail_safety_send_mail_to_dashboard'] = TRUE;
  }
}

/**
 * Use site specific composer_manager dir
 */
if ($all_ini['set_composer_manager_vendor_dir'] && !$is_install) {
  if ($drupal_core >= 8) {
    $config['composer_manager.settings']['vendor_dir'] = 'sites/' . $_SERVER['SERVER_NAME'] . '/vendor';
  }
  else {
    $conf['composer_manager_vendor_dir'] = 'sites/' . $_SERVER['SERVER_NAME'] . '/vendor';
  }
}

if (!empty($is_install)) {
  $da_inc    = FALSE;
}

if (isset($_SERVER['HTTP_USER_AGENT']) && isset($_SERVER['USER_DEVICE'])) {
  $this_device = $_SERVER['USER_DEVICE'];
}
else {
  $this_device = 'normal';
}


/**
 * Logic for non-dev URLs only
 */
if (!$is_dev) {
  if ($all_ini['advagg_auto_configuration']) {

    if ($drupal_core == 6) {
      if (is_readable('modules/o_contrib/advagg/advagg_bundler/advagg_bundler.module') ||
          is_readable('sites/all/modules/advagg/advagg_bundler/advagg_bundler.module')) {
        $conf['preprocess_css'] = 0; // CSS aggregation disabled
        $conf['preprocess_js'] = 0;  // JS aggregation disabled
        $conf['advagg_aggregate_mode'] = 1;
        $conf['advagg_async_generation'] = 1;
        $conf['advagg_checksum_mode'] = "md5";
        $conf['advagg_closure'] = 1;
        $conf['advagg_css_compress_agg_files'] = 1;
        $conf['advagg_css_compress_compressor_level'] = "sane";
        $conf['advagg_css_compress_inline'] = 1;
        $conf['advagg_css_compressor'] = 2;
        $conf['advagg_debug'] = 0;
        $conf['advagg_dir_htaccess'] = 0;
        $conf['advagg_enabled'] = 1;
        $conf['advagg_gzip_compression'] = 1;
        $conf['advagg_js_compress_agg_files'] = 1;
        $conf['advagg_js_compress_callback'] = 1;
        $conf['advagg_js_compress_inline'] = 1;
        $conf['advagg_js_compress_packer_enable'] = 0;
        $conf['advagg_js_compressor'] = 1;
        $conf['advagg_page_cache_mode'] = 0;
        $conf['advagg_rebuild_on_flush'] = 0;
        $conf['advagg_server_addr'] = "-1";
      }
    }
    elseif ($drupal_core == 7) {
      if (is_readable('modules/o_contrib_seven/advagg/advagg_bundler/advagg_bundler.module') ||
          is_readable('sites/all/modules/advagg/advagg_bundler/advagg_bundler.module')) {
        $conf['advagg_bundler_active'] = 1;
        $conf['advagg_cache_level'] = 3;
        $conf['advagg_combine_css_media'] = 0;
        $conf['advagg_core_groups'] = 0;
        $conf['advagg_css_compressor'] = 2;
        $conf['advagg_css_compress_inline'] = 2;
        $conf['advagg_css_compress_inline_if_not_cacheable'] = 1;
        $conf['advagg_enabled'] = 1;
        $conf['advagg_gzip'] = 1;
        $conf['advagg_ie_css_selector_limiter'] = 1;
        $conf['advagg_js_compressor'] = 3;
        $conf['advagg_js_compress_packer'] = 0;
        $conf['advagg_js_compress_inline'] = 3;
        $conf['advagg_js_compress_inline_if_not_cacheable'] = 1;
        $conf['preprocess_css'] = 1;
        $conf['preprocess_js'] = 1;
      }
    }
    elseif ($drupal_core >= 8) {
      if (is_readable('modules/o_contrib_eight/advagg/advagg_bundler/advagg_bundler.module') ||
          is_readable('modules/o_contrib_nine/advagg/advagg_bundler/advagg_bundler.module') ||
          is_readable('modules/o_contrib_ten/advagg/advagg_bundler/advagg_bundler.module') ||
          is_readable('modules/o_contrib_eleven/advagg/advagg_bundler/advagg_bundler.module') ||
          is_readable('modules/advagg/advagg_bundler/advagg_bundler.module') ||
          is_readable('sites/all/modules/advagg/advagg_bundler/advagg_bundler.module')) {
        $config['advagg.settings']['css']['combine_media'] = false;
        $config['advagg.settings']['css']['ie']['limit_selectors'] = true;
        $config['advagg.settings']['cache_level'] = 3;
        $config['advagg.settings']['core_groups'] = false;
        $config['advagg.settings']['enabled'] = true;
        $config['advagg_bundler.settings']['active'] = true;
        $config['advagg_css_minify.settings']['minifier'] = 2;
        $config['advagg_js_minify.settings']['minifier'] = 3;
        $config['system.performance']['css']['preprocess'] = true;
        $config['system.performance']['js']['preprocess'] = true;
      }
    }

    if ($drupal_core == 6 || $drupal_core == 7) {
      if (is_readable('modules/o_contrib/httprl/httprl.module') ||
          is_readable('modules/o_contrib_seven/httprl/httprl.module')) {
        $conf['advagg_use_httprl'] = 1;
        $conf['httprl_background_callback'] = 1;
        $conf['httprl_connect_timeout'] = 3;
        $conf['httprl_dns_timeout'] = 3;
        $conf['httprl_global_timeout'] = "60";
        $conf['httprl_server_addr'] = "-1";
        $conf['httprl_timeout'] = "10";
        $conf['httprl_ttfb_timeout'] = "5";
        // $conf['drupal_http_request_function'] = "httprl_override_core";
      }
    }
  }
}


/**
 * More logic for the front-end only
 */
if (!$is_backend && isset($_SERVER['HTTP_HOST']) &&
    isset($_SERVER['SERVER_NAME'])) {
  if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) || isset($_SERVER['HTTPS'])) {
    $conf['https'] = TRUE;
    $request_type = ($_SERVER['HTTP_X_FORWARDED_PROTO'] == 'https' || $_SERVER['HTTPS'] == 'on') ? 'SSL' : 'NONSSL';
    if ($request_type == "SSL") { // we check for secure connection to set correct base_url
      $base_url = 'https://' . $_SERVER['HTTP_HOST'];
      if ($conf['install_profile'] != 'hostmaster') {
        $_SERVER['HTTPS'] = 'on';
        if ($drupal_core >= 7) {
          ini_set('session.cookie_secure', TRUE);
          if ($is_dev) {
            header('X-Cookie-Sec: YES');
          }
        }
      }
      if ($is_dev) {
        header('X-Local-Proto: https');
      }
    }
    else {
      if ($site_subdir && $raw_host) {
        $base_url = 'http://' . $raw_host . '/' . $site_subdir;
      }
      else {
        $base_url = 'http://' . $_SERVER['HTTP_HOST'];
      }
    }
  }
  else {
    if ($site_subdir && $raw_host) {
      $base_url = 'http://' . $raw_host . '/' . $site_subdir;
    }
    else {
      $base_url = 'http://' . $_SERVER['HTTP_HOST'];
    }
  }

  if ($base_url && $is_dev) {
    header("X-Base-Url: " . $base_url);
  }

  if ($site_subdir && $is_dev) {
    header("X-Site-Subdir: " . $site_subdir);
  }

  if ($all_ini['server_name_cookie_domain']) {
    $domain = '.' . preg_replace('`^www\.`', '', $_SERVER['SERVER_NAME']);
  }
  elseif ($site_subdir && isset($_SERVER['RAW_HOST'])) {
    $domain = '.' . preg_replace('`^www\.`', '', $_SERVER['RAW_HOST']);
  }
  else {
    $domain = '.' . preg_replace('`^www\.`', '', $_SERVER['HTTP_HOST']);
  }
  $domain = str_replace('..', '.', $domain);
  if (count(explode('.', $domain)) > 2 &&
      !is_numeric(str_replace('.', '', $domain))) {
    ini_set('session.cookie_domain', $domain);
    $cookie_domain = $domain;
    header("X-Cookie-Domain: " . $cookie_domain);
  }

  $this_prefix = preg_replace('`^www\.`', '', $_SERVER['SERVER_NAME']) . '_z_';
  if ($is_dev) {
    header("X-Valkey-Prefix: " . $this_prefix);
  }

  if (isset($_SERVER['REQUEST_TIME']) &&
      isset($_SERVER['REMOTE_ADDR']) &&
      isset($_SERVER['HTTP_USER_AGENT']) &&
      !preg_match("/^\/esi\//", $_SERVER['REQUEST_URI'])) {

    // Determine if the site is running on HTTPS
    $request_type = 'NONSSL';
    if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) || isset($_SERVER['HTTPS'])) {
      $request_type = ($_SERVER['HTTP_X_FORWARDED_PROTO'] == 'https' || $_SERVER['HTTPS'] == 'on') ? 'SSL' : 'NONSSL';
    }
    if ($request_type == "SSL") {
      $is_https = TRUE;
      if ($is_dev) {
        header('X-Request-Type:' . $request_type);
      }
    }
    else {
      $is_https = FALSE;
      if ($is_dev) {
        header('X-Request-Type:' . $request_type);
      }
    }

    // Create a unique identifier for the request
    $identity = $_SERVER['REQUEST_TIME'] . $_SERVER['REMOTE_ADDR'] . $_SERVER['SERVER_NAME'] . $_SERVER['HTTP_USER_AGENT'];
    $identity = 'BD' . md5($identity);
    if ($is_dev) {
      header('X-Identity:' . $identity);
    }

    if ($drupal_core >= 8) {
      // Check if the user is logged in by looking for the session cookie.
      // The session cookie name starts with "SESS" or "SSESS" followed by a hash.
      // This check is not site specific in Drupal 8+ like it is in Drupal 7
      // or Drupal 6, but should be sufficient for the intended use case below.
      $cookie_prefix = ini_get('session.cookie_secure') ? 'SSESS' : 'SESS';
      $is_logged_in = FALSE;
      foreach ($_COOKIE as $key => $value) {
        if (strpos($key, $cookie_prefix) == 0) {
          $is_logged_in = TRUE;
          break;
        }
      }
      if ($is_dev) {
        header('X-Cookie-Prefix-A:' . $cookie_prefix);
        header('X-Is-Logged-In-A:' . $is_logged_in);
      }
    }
    elseif ($drupal_core == 7) {
      // For Drupal 7 use sha256 hash and cookie prefix based on session.cookie_secure
      $cookie_prefix = ini_get('session.cookie_secure') ? 'SSESS' : 'SESS';
      $test_sess_name = $cookie_prefix . substr(hash('sha256', $cookie_domain), 0, 32);
      if ($is_dev) {
        header('X-Cookie-Prefix-B:' . $cookie_prefix);
        header('X-Test-Sess-Name-B:' . $test_sess_name);
      }
    }
    else {
      // For Drupal 6 use md5 hash and SESS prefix only
      $cookie_prefix = 'SESS';
      $test_sess_name = $cookie_prefix . md5($cookie_domain);
      if ($is_dev) {
        header('X-Cookie-Prefix-C:' . $cookie_prefix);
        header('X-Test-Sess-Name-C:' . $test_sess_name);
      }
    }

    // Check if the session cookie is present
    if (isset($_COOKIE[$test_sess_name]) || $is_logged_in) {
      $is_anon = 'LOGGED';
    }
    else {
      $is_anon = 'ANONYMOUS';
    }
    if ($is_dev) {
      header('X-Is-Anon:' . $is_anon);
    }

    // Redirect not logged in visitors to homepage to protect admin URLs from bots
    if ($is_anon == 'ANONYMOUS') {
      if (preg_match("/\/(?:node\/[0-9]+\/edit|node\/add)/", $_SERVER['REQUEST_URI'])) {
        if (empty($all_ini['allow_anon_node_add'])) {
          header("Location: " . $base_url . "/", true, 301);
          exit;
        }
      }
      if (preg_match("/^\/(?:[a-z]{2}\/)?(?:admin|logout|privatemsg|approve)/", $_SERVER['REQUEST_URI'])) {
        if (empty($all_ini['disable_admin_dos_protection'])) {
          header("Location: " . $base_url . "/", true, 301);
          exit;
        }
      }
    }

    // Additional logic for caching or other needs
    if ($is_anon == 'ANONYMOUS' && !empty($all_ini['speed_booster_anon_cache_ttl']) && preg_match("/^[0-9]{2,}$/", $all_ini['speed_booster_anon_cache_ttl'])) {
      if ($all_ini['speed_booster_anon_cache_ttl'] > 10) {
        $expire_in_seconds = $all_ini['speed_booster_anon_cache_ttl'];
        header('X-Limit-Booster:' . $all_ini['speed_booster_anon_cache_ttl']);
      }
    }

    // Prevent turning the feature server site into a spam machine
    // Disable self-registration also on hostmaster
    if ($conf['install_profile'] == 'feature_server' ||
        $conf['install_profile'] == 'hostmaster') {
      $conf['user_register'] = 0; // Force "Only site administrators can create new user accounts"
    }
    if (!$is_bot && !$high_traffic) {
      if (preg_match("/^\/(?:[a-z]{2}\/)?(?:admin|cart|checkout|logout|privatemsg)/", $_SERVER['REQUEST_URI']) ||
          preg_match("/\/(?:node\/[0-9]+\/edit|node\/add|comment\/reply|approve|ajax_comments|commerce_currency_select)/", $_SERVER['REQUEST_URI']) ||
          preg_match("/(?:^dev\.|\.dev\.|\.devel\.)/", $_SERVER['HTTP_HOST'])) {
        $expire_in_seconds = '1';
        header('X-Limit-Booster: 1');
      }
      if (isset($_SERVER['REQUEST_URI']) &&
          preg_match("/(?:x-progress-id|ahah|progress\/|autocomplete|ajax|batch|js\/.*)/i", $_SERVER['REQUEST_URI'])) {
        $expire_in_seconds = '0';
        if ($is_dev) {
          header('X-Skip-Booster: AjaxRU');
        }
      }
      if (isset($_SERVER['QUERY_STRING']) &&
          preg_match("/(?:x-progress-id|ahah|progress\/|autocomplete|ajax|batch|js\/.*)/i", $_SERVER['QUERY_STRING'])) {
        $expire_in_seconds = '0';
        if ($is_dev) {
          header('X-Skip-Booster: AjaxQS');
        }
      }
      if (isset($_SERVER['REQUEST_METHOD']) &&
          $_SERVER['REQUEST_METHOD'] == 'POST') {
        if (!isset($_COOKIE['NoCacheID'])) {
          $lifetime = '15';
          setcookie('NoCacheID', 'POST' . $identity, $_SERVER['REQUEST_TIME'] + $lifetime, '/', $cookie_domain);
        }
        $expire_in_seconds = '0';
        if ($is_dev) {
          header('X-Skip-Booster: PostRM');
        }
      }
    }
    if ($is_bot) {
      if (!preg_match("/Pingdom/i", $_SERVER['HTTP_USER_AGENT']) &&
          !preg_match("/(?:rss|feed)/i", $_SERVER['REQUEST_URI'])) {
        $expire_in_seconds = '3600';
        if ($is_dev) {
          header('X-Bot-Booster: 3600');
        }
      }
    }
    if ($conf['install_profile'] != 'hostmaster' && ($expire_in_seconds > -1)) {
      header("X-Accel-Expires: " . $expire_in_seconds);
      if ($expire_in_seconds > -1 && $expire_in_seconds < 2) {
        $conf['cache'] = 0; // Disable page caching on the fly
      }
    }
  }
}


/**
 * Support files/styles with short URIs also for files not generated yet
 */
if (preg_match("/^\/files\/styles\//", $_SERVER['REQUEST_URI'])) {
  header("Location: " . $base_url . "/sites/" . $_SERVER['SERVER_NAME'] . $_SERVER['REQUEST_URI'], true, 301);
  exit;
}


/**
 * Optional system level overrides
 */
if (is_readable('/data/conf/override.global.inc')) {
  require_once "/data/conf/override.global.inc";
}

/**
 * Use Redis caching and lock support only for d6 and d7 profiles
 */
if ($valkey_up && $use_valkey && !$custom_cache) {
  $cache_backport = FALSE;
  $cache_valkey = FALSE;
  $all_ini['redis_use_modern'] = TRUE;
  if ($all_ini['redis_use_modern']) {
    if ($drupal_core >= 8) {
      $redis_comprs = TRUE;
      $redis_dirname = 'redis_eight';
      if (!$all_ini['redis_old_eight_mode']) {
        $redis_dirname = 'redis_compr';
      }
      if ($drupal_core == 10 || $drupal_core == 11) {
        $redis_new_dirname = 'redis_ten_eleven';
        $redis_legacy_dirname = 'redis_nine_ten';
        if (is_readable('modules/o_contrib_ten/' . $redis_new_dirname . '/redis.services.yml')) {
          $redis_dirname = $redis_new_dirname;
        }
        elseif (is_readable('modules/o_contrib_ten/' . $redis_legacy_dirname . '/redis.services.yml')) {
          $redis_dirname = $redis_legacy_dirname;
        }
      }
      elseif ($drupal_core == 9) {
        $redis_dirname = 'redis_nine_ten';
        if ($all_ini['redis_old_nine_mode']) {
          $redis_dirname = 'redis_compr';
        }
      }
    }
    else {
      $redis_dirname = 'redis_edge';
    }
    if ($is_dev && !$is_backend) {
      header("X-Valkey-Version-Is: Modern");
      header("X-Valkey-Dir-Is: " . $redis_dirname);
    }
    if ($all_ini['redis_flush_forced_mode']) {
      if ($drupal_core >= 8) {
        $settings['redis_perm_ttl']                 = 86400; // 24 hours max
        $settings['redis_flush_mode']               = 1; // Valkey default is 0
        $settings['redis_flush_mode_cache_page']    = 2; // Valkey default is 1
        $settings['redis_flush_mode_cache_block']   = 2; // Valkey default is 1
        $settings['redis_flush_mode_cache_menu']    = 2; // Valkey default is 0
        $settings['redis_flush_mode_cache_metatag'] = 2; // Valkey default is 0
      }
      else {
        $conf['redis_perm_ttl']                 = 86400; // 24 hours max
        $conf['redis_flush_mode']               = 1; // Valkey default is 0
        $conf['redis_flush_mode_cache_page']    = 2; // Valkey default is 1
        $conf['redis_flush_mode_cache_block']   = 2; // Valkey default is 1
        $conf['redis_flush_mode_cache_menu']    = 2; // Valkey default is 0
        $conf['redis_flush_mode_cache_metatag'] = 2; // Valkey default is 0
      }
      // See http://bit.ly/1drmi35 for more information
      if ($is_dev && !$is_backend) {
        header("X-Valkey-Flush-Forced-Mode: Forced");
      }
    }
  }
  else {
    $redis_dirname = 'redis';
    if ($is_dev && !$is_backend) {
      header("X-Valkey-Version-Is: Legacy");
      header("X-Valkey-Dir-Is: " . $redis_dirname);
    }
  }
  if ($drupal_core >= 8) {
    if (file_exists('sites/' . $_SERVER['SERVER_NAME'] . '/.redisLegacyOff')) {
      if ($is_dev && !$is_backend) {
        header("X-Valkey-Off-Ctrl-Exists: .redisLegacyOff");
      }
    }
    else {
      if (is_readable('sites/' . $_SERVER['SERVER_NAME'] . '/files/development.services.yml')) {
        if ($is_dev && !$is_backend) {
          header("X-Dev-Services-Yml-Is-Readable: development.services.yml");
        }
      }
      else {
        if (is_readable('modules/o_contrib_ten')) {
          if (is_readable('modules/o_contrib_ten/' . $redis_dirname . '/example.services.yml')) {
            $cache_valkey = TRUE;
            $example_failover_path = 'modules/o_contrib_ten/' . $redis_dirname . '/example.failover.services.yml';
            $example_services_path = 'modules/o_contrib_ten/' . $redis_dirname . '/example.services.yml';
            $cache_gzip_path = 'modules/o_contrib_ten/' . $redis_dirname . '/lib/Redis/CacheCompressed.php';
          }
          if (is_readable('modules/o_contrib_ten/' . $redis_dirname . '/redis.services.yml')) {
            $cache_valkey = TRUE;
            $redis_services_path = 'modules/o_contrib_ten/' . $redis_dirname . '/redis.services.yml';
            if ($is_dev && !$is_backend) {
              header("X-Valkey-Services-Is-Readable: " . $redis_services_path);
            }
          }
        }
        elseif (is_readable('modules/o_contrib_eleven')) {
          if (is_readable('modules/o_contrib_eleven/' . $redis_dirname . '/example.services.yml')) {
            $cache_valkey = TRUE;
            $example_failover_path = 'modules/o_contrib_eleven/' . $redis_dirname . '/example.failover.services.yml';
            $example_services_path = 'modules/o_contrib_eleven/' . $redis_dirname . '/example.services.yml';
            $cache_gzip_path = 'modules/o_contrib_eleven/' . $redis_dirname . '/lib/Redis/CacheCompressed.php';
          }
          if (is_readable('modules/o_contrib_eleven/' . $redis_dirname . '/redis.services.yml')) {
            $cache_valkey = TRUE;
            $redis_services_path = 'modules/o_contrib_eleven/' . $redis_dirname . '/redis.services.yml';
            if ($is_dev && !$is_backend) {
              header("X-Valkey-Services-Is-Readable: " . $redis_services_path);
            }
          }
        }
        elseif (is_readable('modules/o_contrib_nine')) {
          if (is_readable('modules/o_contrib_nine/' . $redis_dirname . '/example.services.yml')) {
            $cache_valkey = TRUE;
            $example_failover_path = 'modules/o_contrib_nine/' . $redis_dirname . '/example.failover.services.yml';
            $example_services_path = 'modules/o_contrib_nine/' . $redis_dirname . '/example.services.yml';
            $cache_gzip_path = 'modules/o_contrib_nine/' . $redis_dirname . '/lib/Redis/CacheCompressed.php';
          }
          if (is_readable('modules/o_contrib_nine/' . $redis_dirname . '/redis.services.yml')) {
            $cache_valkey = TRUE;
            $redis_services_path = 'modules/o_contrib_nine/' . $redis_dirname . '/redis.services.yml';
            if ($is_dev && !$is_backend) {
              header("X-Valkey-Services-Is-Readable: " . $redis_services_path);
            }
          }
        }
        elseif (is_readable('modules/o_contrib_eight')) {
          if (is_readable('modules/o_contrib_eight/' . $redis_dirname . '/example.services.yml')) {
            $cache_valkey = TRUE;
            $example_services_path = 'modules/o_contrib_eight/' . $redis_dirname . '/example.services.yml';
            $cache_gzip_path = 'modules/o_contrib_eight/' . $redis_dirname . '/lib/Redis/CacheCompressed.php';
            if ($is_dev && !$is_backend) {
              header("X-Example-Services-Is-Readable: " . $example_services_path);
            }
          }
          if (is_readable('modules/o_contrib_eight/' . $redis_dirname . '/redis.services.yml')) {
            $cache_valkey = TRUE;
            $redis_services_path = 'modules/o_contrib_eight/' . $redis_dirname . '/redis.services.yml';
            if ($is_dev && !$is_backend) {
              header("X-Valkey-Services-Is-Readable: " . $redis_services_path);
            }
          }
        }
      }
    }
  }
  elseif ($drupal_core == 7) {
    if (is_readable('modules/o_contrib_seven/' . $redis_dirname . '/redis.autoload.inc')) {
      $cache_valkey = TRUE;
      $cache_backport = FALSE;
      $cache_redis_path = 'modules/o_contrib_seven/' . $redis_dirname . '/redis.autoload.inc';
      $cache_lock_path = 'modules/o_contrib_seven/' . $redis_dirname . '/redis.lock.inc';
      $cache_path_path = 'modules/o_contrib_seven/' . $redis_dirname . '/redis.path.inc';
      $cache_gzip_path = 'modules/o_contrib_seven/' . $redis_dirname . '/lib/Redis/CacheCompressed.php';
      if ($is_dev && !$is_backend) {
        header("X-Valkey-Autoload-Is-Readable: " . $cache_redis_path);
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
  elseif ($drupal_core == 6) {
    if (is_readable('modules/o_contrib/cache_backport/cache.inc')) {
      $cache_backport = TRUE;
      $cache_backport_path = 'modules/o_contrib/cache_backport/cache.inc';
      if ($is_dev && !$is_backend) {
        header("X-Valkey-Cache-Backport-Is-Readable: " . $cache_backport_path);
      }
    }
    if (is_readable('modules/o_contrib/' . $redis_dirname . '/redis.autoload.inc')) {
      $cache_valkey = TRUE;
      $cache_redis_path = 'modules/o_contrib/' . $redis_dirname . '/redis.autoload.inc';
      $cache_lock_path = 'modules/o_contrib/' . $redis_dirname . '/redis.lock.inc';
      $cache_path_path = 'modules/o_contrib/' . $redis_dirname . '/redis.path.inc';
      $cache_gzip_path = 'modules/o_contrib/' . $redis_dirname . '/lib/Redis/CacheCompressed.php';
      if ($is_dev && !$is_backend) {
        header("X-Valkey-Autoload-Is-Readable: " . $cache_redis_path);
      }
    }
  }
  if ($cache_valkey) {
    if ($drupal_core >= 8) {
      if (is_readable('modules/o_contrib_eleven/' . $redis_dirname . '/redis.services.yml')) {
        $class_loader->addPsr4('Drupal\\redis\\', 'modules/o_contrib_eleven/' . $redis_dirname . '/src');
      }
      elseif (is_readable('modules/o_contrib_ten/' . $redis_dirname . '/redis.services.yml')) {
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
        $settings['cache']['bins']['bootstrap']  = 'cache.backend.chainedfast';
        $settings['cache']['bins']['discovery']  = 'cache.backend.chainedfast';
        $settings['cache']['bins']['config']     = 'cache.backend.chainedfast';
      }
      $settings['container_yamls'][]             = $example_services_path;
      $settings['container_yamls'][]             = $redis_services_path;
      if ($drupal_core <= 10) {
        $settings['queue_default']               = 'queue.redis_reliable';
      }
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
          header("X-Valkey-Lock-Is-Readable: " . $cache_lock_path);
        }
      }
      if (is_readable($cache_path_path) && $redis_path) {
        $conf['path_inc']                       = $cache_path_path;
        $conf['path_alias_admin_blacklist']     = FALSE;
        if ($is_dev && !$is_backend) {
          header("X-Valkey-Path-Is-Readable: " . $cache_path_path);
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
      $conf['page_cache_invoke_hooks']          = TRUE;  // D7 == Do not use Aggressive Mode
      $conf['page_cache_without_database']      = FALSE; // D7 == Do not use Aggressive Mode
      $conf['page_cache_maximum_age']           = 0;     // D7 == max-age in the Cache-Control header (ignored by Speed Booster)
      $conf['page_cache_max_age']               = 0;     // D6 == max-age in the Cache-Control header (ignored by Speed Booster)
      $conf['cache_lifetime']                   = 0;     // D7 == BOA uses Speed Booster / Nginx micro-caching instead
      $conf['page_cache_lifetime']              = 0;     // D6 == BOA uses Speed Booster / Nginx micro-caching instead
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
          header("X-Ini-Valkey-Exclude-Bin-" . $exclude . ": " . $bin_exclude);
        }
      }
    }
  }
}


/**
 * Drupal for Facebook (fb)
 *
 * Important:
 * Facebook client libraries will not work properly if arg_separator.output is not &
 * The default value is &amp;. Change this in settings.php. Make the value "&"
 * https://drupal.org/node/205476
 */
if (!$custom_fb && $all_ini['auto_detect_facebook_integration']) {
  if (is_readable('sites/all/modules/fb/fb_settings.inc')) {
    ini_set('arg_separator.output', '&');
    require_once "sites/all/modules/fb/fb_settings.inc";
    $conf['fb_api_file'] = "sites/all/modules/fb/facebook-platform/php/facebook.php";
  }
  elseif (is_readable('sites/all/modules/contrib/fb/fb_settings.inc')) {
    ini_set('arg_separator.output', '&');
    require_once "sites/all/modules/contrib/fb/fb_settings.inc";
    $conf['fb_api_file'] = "sites/all/modules/contrib/fb/facebook-platform/php/facebook.php";
  }
  elseif (is_readable('profiles/' . $conf['install_profile'] . '/modules/fb/fb_settings.inc')) {
    ini_set('arg_separator.output', '&');
    require_once 'profiles/' . $conf['install_profile'] . '/modules/fb/fb_settings.inc';
    $conf['fb_api_file'] = 'profiles/' . $conf['install_profile'] . '/modules/fb/facebook-platform/php/facebook.php';
  }
  elseif (is_readable('profiles/' . $conf['install_profile'] . '/modules/contrib/fb/fb_settings.inc')) {
    ini_set('arg_separator.output', '&');
    require_once 'profiles/' . $conf['install_profile'] . '/modules/contrib/fb/fb_settings.inc';
    $conf['fb_api_file'] = 'profiles/' . $conf['install_profile'] . '/modules/contrib/fb/facebook-platform/php/facebook.php';
  }
}


/**
 * Domain module
 */
if (!$custom_da) {
  if ($da_inc) {
    require_once($da_inc);
  }
}


/**
 * New Relic Integration for Drupal with Drush Compatibility (8, 12, 13)
 *
 * Supports background jobs and sets appropriate New Relic parameters.
 */
if (extension_loaded('newrelic') && !empty($all_ini['enable_newrelic_integration'])) {
  $this_instance = FALSE;

  if ($is_backend) {
    $uri = FALSE;

    // Check if drush_get_context exists (Drush 8)
    if (function_exists('drush_get_context')) {
      // Drush 8 context retrieval
      $context = drush_get_context();
      if (isset($context['DRUSH_URI'])) {
        $uri = $context['DRUSH_URI'];
      }
      elseif (isset($context['DRUSH_DRUPAL_SITE'])) {
        $uri = $context['DRUSH_DRUPAL_SITE'];
      }
    }
    else {
      // Drush 9+ context retrieval
      // Attempt to retrieve URI from environment variables or Drush services
      // Drush commands can pass the URI as an environment variable or argument

      // Example: Using environment variable (you might need to set this in Drush commands)
      if (isset($_SERVER['DRUSH_URI'])) {
        $uri = $_SERVER['DRUSH_URI'];
      }
      elseif (isset($_SERVER['DRUPAL_SITE_URI'])) {
        $uri = $_SERVER['DRUPAL_SITE_URI'];
      }
      else {
        // Fallback: Attempt to determine URI using Drupal APIs
        // Note: In Drush context, some Drupal services might not be fully bootstrapped
        try {
          $request = \Drupal::request();
          $uri = $request->getSchemeAndHttpHost();
        }
        catch (\Exception $e) {
          // Unable to determine URI; proceed without setting it
        }
      }
    }

    if ($uri) {
      // Clean the URI by removing the scheme
      $uri = str_replace(['http://', 'https://'], '', $uri);
      $this_instance = 'Drush Site: ' . $uri;

      // Set New Relic transaction name and parameters if command details are available
      if (isset($command['command']) && isset($command['arguments'])) {
        $drush_command = array_merge([$command['command']], $command['arguments']);
        $command_str = implode(' ', $drush_command);

        // Add custom parameters to New Relic
        newrelic_add_custom_parameter('Drush command', $command_str);
        newrelic_name_transaction($command_str);

        // Indicate that this is a background job
        newrelic_background_job(TRUE);
      }
    }
  }
  else {
    // Non-Drush (web request) context
    if (isset($_SERVER['SERVER_NAME'])) {
      $this_instance = 'Web Site: ' . $_SERVER['SERVER_NAME'];
      // Optionally, indicate this is not a background job
      // newrelic_background_job(FALSE);
    }
  }

  // Apply the New Relic app name if determined
  if ($this_instance) {
    ini_set('newrelic.appname', $this_instance);
    newrelic_set_appname($this_instance);
  }
}
elseif (extension_loaded('newrelic') && empty($all_ini['enable_newrelic_integration'])) {
  // Disable New Relic auto-RUM and ignore transactions if integration is disabled
  newrelic_disable_autorum();
  newrelic_ignore_apdex();
  newrelic_ignore_transaction();
}


/**
 * Unset config arrays on non-dev URLs
 */
if (!$is_dev) {
  unset($boa_ini);
  unset($usr_plr_ini);
  unset($usr_loc_ini);
  unset($all_ini);
}
