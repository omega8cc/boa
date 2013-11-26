<?php # global settings.php

error_reporting(0); // Disable reporting errors by default - enable later only for foo.dev.domain subdomains

// Fix for Mollom, CloudFlare and others running via Proxy
if (isset($_SERVER['REMOTE_ADDR'])) {
  if (isset($_SERVER['HTTP_X_FORWARDED_FOR'])) {
    $_SERVER['REMOTE_ADDR'] = $_SERVER['HTTP_X_FORWARDED_FOR'];
  }
  if (isset($_SERVER['HTTP_X_REAL_IP'])) {
    $_SERVER['REMOTE_ADDR'] = $_SERVER['HTTP_X_REAL_IP'];
  }
  if (isset($_SERVER['HTTP_CF_CONNECTING_IP'])) {
    $_SERVER['REMOTE_ADDR'] = $_SERVER['HTTP_CF_CONNECTING_IP'];
  }
}

// Required for proper Redis support on command line / via Drush
if (isset($_SERVER['HTTP_HOST']) && !isset($_SERVER['SERVER_NAME'])) {
  $_SERVER['SERVER_NAME'] = $_SERVER['HTTP_HOST'];
}

/**
 * Forced defaults
 */
$conf['page_compression'] = 0;    // Required in Nginx, since it already compresses everything
$conf['boost_crawl_on_cron'] = 0; // Deny Boost crawler
$conf['cron_safe_threshold'] = 0; // Disable poormanscron
$conf['preprocess_css'] = 1;      // Enable hardcoded css aggregation
$conf['preprocess_js'] = 1;       // Enable hardcoded js aggregation
$conf['file_downloads'] = 1;      // Force public downloads by default
$conf['error_level'] = 0;         // Disable errors on screen
$conf['statistics_enable_access_log'] = 0;   // Disable access log stats
$conf['allow_authorize_operations'] = false; // Disable insecure plugin manager
$conf['admin_menu_cache_client'] = false;    // Disable caching in admin_menu #442560
$conf['boost_ignore_htaccess_warning'] = 1;  // Silence false alarm in boost
$conf['expire_flush_front'] = 1;             // Default settings for expire module
$conf['expire_flush_node_terms'] = 1;        // Default settings for expire module
$conf['expire_flush_menu_items'] = 0;        // Default settings for expire module
$conf['expire_flush_cck_references'] = 0;    // Default settings for expire module
$conf['expire_include_base_url'] = 1;        // Default settings for expire module
$conf['video_ffmpeg_instances'] = 1;         // Force safe default for ffmpeg
$conf['securepages_enable'] = 1;             // Force to avoid issues with ssl proxy
$conf['drupal_http_request_fails'] = false;  // Avoid false alarm
$conf['image_allow_insecure_derivatives'] = true; // Enable to avoid known issues: http://drupal.org/drupal-7.20-release-notes
$conf['theme_cloudy_settings']['omega_rebuild_aggregates'] = false;     // Do not allow to turn it on by default
$conf['theme_cloudy_settings']['omega_rebuild_theme_registry'] = false; // Do not allow to turn it on by default
$update_free_access = FALSE;
ini_set('session.cache_expire', 86400);    // Set it also to 24 hours max
ini_set('session.gc_maxlifetime', 86400);  // Set it also to 24 hours max
ini_set('auto_detect_line_endings', TRUE); // http://drupal.org/node/912682
// Improve sessions management if module session_expire and/or Pressflow core is not used
// It is already enabled in the php.ini, but we are forcing it here, just in case
ini_set('session.gc_probability', 1);
ini_set('session.gc_divisor', 1000);
if ($conf['install_profile'] == 'totem') {
  ini_set('session.cookie_lifetime', 0); // Force log-out on browser quit
}
else {
  ini_set('session.cookie_lifetime', 86400); // Set it to 24 hours max
}

/**
 * Vars init
 */
$custom_cache = FALSE;
$custom_da    = FALSE;
$custom_fb    = FALSE;
$da_inc       = FALSE;
$deny_anon    = FALSE;
$drupal_eight = FALSE;
$drupal_five  = FALSE;
$drupal_seven = FALSE;
$drupal_six   = FALSE;
$high_traffic = FALSE;
$ini_loc_src  = FALSE;
$ini_plr_src  = FALSE;
$is_backend   = FALSE;
$is_dev       = FALSE;
$is_install   = FALSE;
$is_test      = FALSE;
$known_bot    = FALSE;
$redis_lock   = FALSE;
$redis_up     = FALSE;
$use_redis    = FALSE;
$usr_loc_ini  = FALSE;
$usr_plr_ini  = FALSE;

/**
 * Bots detection
 */
if (isset($_SERVER['HTTP_USER_AGENT']) && preg_match("/(?:crawl|bot|spider|tracker|click|parser|google|yahoo|yandex|baidu|bing)/i", $_SERVER['HTTP_USER_AGENT'])) {
  // Detect known bots
  $known_bot = TRUE;
}

/**
 * Backend and task detection
 */
if (function_exists('drush_get_command')) {
  $command = drush_get_command();
  $command = explode(" ", $command['command']);
  if ($command && !preg_match("/^help/", $command[0])) {
    $is_backend = TRUE;
  }
  if (preg_match("/^provision-install/", $command[0])) {
    $is_install = TRUE;
  }
}

/**
 * Dev mode detection and URLs protection
 */
if (isset($_SERVER['HTTP_HOST']) && preg_match("/(?:^dev\.|\.dev\.|\.devel\.)/i", $_SERVER['HTTP_HOST']) && isset($_SERVER['HTTP_USER_AGENT'])) {
  // Deny known search bots on ^(dev|foo.(dev|devel)).domain subdomains
  if ($known_bot && !$is_backend) {
    header('X-Accel-Expires: 5');
    header("HTTP/1.1 301 Moved Permanently");
    header("Location: http://www.aegirproject.org/");
    header("Connection: close");
    exit;
  }
  $is_dev = TRUE;
}

/**
 * Core detection and Caching auto-conf
 */
if (file_exists('web.config')) {
  if (file_exists('core')) {
    $conf['cache'] = 1; // Enable hardcoded standard caching - Drupal 8
    $drupal_eight = TRUE;
    if ($is_dev && !$is_backend) {
      header('X-Backend: A');
    }
  }
  else {
    $conf['cache'] = 1; // Enable hardcoded standard caching - Drupal 7
    $drupal_seven = TRUE;
    $use_redis = TRUE;
    if ($is_dev && !$is_backend) {
      header('X-Backend: B');
    }
  }
}
elseif (file_exists('modules/path_alias_cache')) {
  $conf['cache'] = 1; // Enable hardcoded standard caching - Pressflow 6
  $drupal_six = TRUE;
  $use_redis = TRUE;
  if ($is_dev && !$is_backend) {
    header('X-Backend: C');
  }
}
elseif (file_exists('modules/watchdog')) {
  $conf['cache'] = 1; // Enable hardcoded standard caching - Pressflow 5
  $drupal_five = TRUE;
  if ($is_dev && !$is_backend) {
    header('X-Backend: D');
  }
}
else {
  $conf['cache'] = 1; // Enable hardcoded standard caching
  $drupal_unknown = TRUE;
  if ($is_dev && !$is_backend) {
    header('X-Backend: E');
  }
}

/**
 * CI URLs protection
 */
if (isset($_SERVER['HTTP_HOST']) && preg_match("/\.(?:host8|aegir|boa|o8)\.(?:biz|cc|io)$/i", $_SERVER['HTTP_HOST'])) {
  // Deny known search bots on some protected CI subdomains
  if ($known_bot && !$is_backend) {
    header('X-Accel-Expires: 5');
    header("HTTP/1.1 301 Moved Permanently");
    header("Location: https://omega8.cc/");
    header("Connection: close");
    exit;
  }
}

/**
 * Test and tmp URLs protection
 */
if (isset($_SERVER['HTTP_HOST']) && preg_match("/(?:^tmp\.|\.test\.|\.tmp\.)/i", $_SERVER['HTTP_HOST']) && isset($_SERVER['HTTP_USER_AGENT'])) {
  // Deny known search bots on ^(tmp|foo.(tmp|test)).domain subdomains
  if ($known_bot && !$is_backend) {
    header('X-Accel-Expires: 5');
    header("HTTP/1.1 301 Moved Permanently");
    header("Location: http://www.aegirproject.org/");
    header("Connection: close");
    exit;
  }
  $is_test = TRUE;
}

/**
 * Dev mode switch
 */
if ($is_dev && !$is_backend) {
  error_reporting(E_ALL & ~E_NOTICE);
  ini_set('display_errors', TRUE);
  ini_set('display_startup_errors', TRUE);
  ini_set('opcache.revalidate_freq', '1');
  unset($conf['cache']);          // Stop hardcoding caching
  unset($conf['preprocess_css']); // Stop hardcoding css aggregation
  unset($conf['preprocess_js']);  // Stop hardcoding js aggregation
  unset($conf['theme_cloudy_settings']['omega_rebuild_aggregates']);     // Do not force on dev URLs
  unset($conf['theme_cloudy_settings']['omega_rebuild_theme_registry']); // Do not force on dev URLs
  unset($conf['error_level']);    // Stop hardcoding no errors on screen
  $conf['xmlsitemap_submit'] = 0; // Disable XML Sitemap for foo.dev.domain
  $conf['xmlsitemap_update'] = 0; // Disable XML Sitemap for foo.dev.domain
}

/**
 * Set sane default opcache TTL on non-dev sites
 */
if (!$is_dev && !$is_backend) {
  ini_set('opcache.revalidate_freq', '5');
}

/**
 * BOA INI defaults
 */
$boa_ini = array(
  'redis_use_modern' => FALSE,
  'redis_flush_forced_mode' => FALSE,
  'redis_lock_enable' => FALSE,
  'redis_cache_disable' => FALSE,
  'speed_booster_anon_cache_ttl' => FALSE,
  'allow_anon_node_add' => FALSE,
  'disable_admin_dos_protection' => FALSE,
  'allow_private_file_downloads' => FALSE,
  'server_name_cookie_domain' => FALSE,
  'auto_detect_facebook_integration' => TRUE,      // For backward compatibility until next release, then FALSE
  'auto_detect_domain_access_integration' => TRUE, // For backward compatibility until next release, then FALSE
  'advagg_auto_configuration' => FALSE, // Will be set to TRUE in boa_site_control.ini if the module is enabled
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
if (is_readable('sites/'. $_SERVER['SERVER_NAME'] .'/modules/boa_site_control.ini')) {
  $ini_loc_src = 'sites/'. $_SERVER['SERVER_NAME'] .'/modules/boa_site_control.ini';
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
  header("X-Ini-Redis-Use-Modern: " . $all_ini['redis_use_modern']);
  header("X-Ini-Redis-Flush-Forced-Mode: " . $all_ini['redis_flush_forced_mode']);
  header("X-Ini-Redis-Lock-Enable: " . $all_ini['redis_lock_enable']);
  header("X-Ini-Redis-Cache-Disable: " . $all_ini['redis_cache_disable']);
  header("X-Ini-Speed-Booster-Anon-Cache-Ttl: " . $all_ini['speed_booster_anon_cache_ttl']);
  header("X-Ini-Allow-Anon-Node-Add: " . $all_ini['allow_anon_node_add']);
  header("X-Ini-Disable-Admin-Dos-Protection: " . $all_ini['disable_admin_dos_protection']);
  header("X-Ini-Allow-Private-File-Downloads: " . $all_ini['allow_private_file_downloads']);
  header("X-Ini-Server-Name-Cookie-Domain: " . $all_ini['server_name_cookie_domain']);
  header("X-Ini-Auto-Detect-Facebook-Integration: " . $all_ini['auto_detect_facebook_integration']);
  header("X-Ini-Auto-Detect-Domain-Access-Integration: " . $all_ini['auto_detect_domain_access_integration']);
  header("X-Ini-Advagg-Auto-Configuration: " . $all_ini['advagg_auto_configuration']);
  header("X-Ini-Sql-Conversion-Mode: " . $all_ini['sql_conversion_mode']);
  header("X-Ini-Enable-User-Register-Protection: " . $all_ini['enable_user_register_protection']);
  header("X-Ini-Entitycache-Dont-Enable: " . $all_ini['entitycache_dont_enable']);
  header("X-Ini-Views-Cache-Bully-Dont-Enable: " . $all_ini['views_cache_bully_dont_enable']);
  header("X-Ini-Views-Content-Cache-Dont-Enable: " . $all_ini['views_content_cache_dont_enable']);
  header("X-Ini-Disable-User-Register-Protection: " . $all_ini['disable_user_register_protection']);
}

/**
 * Hostmaster specific settings
 */
if ($conf['install_profile'] == 'hostmaster' && isset($_SERVER['HTTP_USER_AGENT'])) {
  if (!file_exists('/data/conf/no-https-aegir.inc')) {
    $request_type = ($_SERVER['HTTP_X_FORWARDED_PROTO'] == 'https' || $_SERVER['HTTPS'] == 'on') ? 'SSL' : 'NONSSL';
    if ($request_type != "SSL" && !preg_match("/^\/cron\.php/", $_SERVER['REQUEST_URI']) && !$is_backend) { // we force secure connection here
      header('X-Accel-Expires: 5');
      header("HTTP/1.1 301 Moved Permanently");
      header("Location: https://" . $_SERVER['HTTP_HOST'] . $_SERVER['REQUEST_URI']);
      header("Connection: close");
      exit;
    }
  }
  $conf['hosting_require_disable_before_delete'] = 0;
  unset($conf['cache']); // Disable hardcoded caching
  ini_set('session.cookie_lifetime', 0); // Force log-out on browser quit
  if (preg_match("/(?:host8|omega8|aegir\.cc)/i", $_SERVER['HTTP_HOST']) && !$is_backend) {
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
  if (!$is_backend) {
    header('X-Accel-Expires: 1');
  }
}

/**
 * Main section starts here
 */

if (isset($_SERVER['SERVER_NAME']) && $all_ini['allow_private_file_downloads']) {
  unset($conf['file_downloads']); // Disable hardcoded public downloads
  if ($is_dev && !$is_backend) {
    header('X-Is-Cart: YES');
  }
}

if (isset($_SERVER['SERVER_NAME']) && $all_ini['redis_cache_disable']) {
  $use_redis = FALSE;
}

if (isset($_SERVER['REQUEST_URI']) && preg_match("/noredis=1/", $_SERVER['REQUEST_URI'])) {
  $use_redis = FALSE;
}

if ($use_redis && !$is_install && !$custom_cache) {
  $redis = new Redis();
  $redis->connect('127.0.0.1', 6379);
  if ($redis->IsConnected()) {
    $redis->auth('isfoobared');
    $response = $redis->ping();
    if (strpos($response, 'PONG')) {
      $redis_up = TRUE;
    }
    $redis->close();
  }
}

if ($redis_up && $use_redis) {
  if ($is_dev && !$is_backend) {
    header('X-Allow-Redis: YES');
  }
}
else {
  if ($is_dev && !$is_backend) {
    header('X-Allow-Redis: NO');
  }
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

if ($is_install) {
  $use_redis = FALSE;
  $da_inc    = FALSE;
}

if (isset($_SERVER['HTTP_HOST']) && isset($_SERVER['SERVER_NAME'])) {

  if (isset($_SERVER['HTTP_USER_AGENT']) && isset($_SERVER['USER_DEVICE'])) {
    $this_device = $_SERVER['USER_DEVICE'];
  }
  else {
    $this_device = 'normal';
  }

  if (!$is_dev && $drupal_six && $all_ini['advagg_auto_configuration'] && (is_readable('modules/o_contrib/advagg/advagg_bundler/advagg_bundler.module') ||
      is_readable('sites/all/modules/advagg/advagg_bundler/advagg_bundler.module'))) {
    $conf['preprocess_css'] = 0; // css aggregation disabled
    $conf['preprocess_js'] = 0;  // js aggregation disabled
    $conf['advagg_aggregate_mode'] = 1;
    $conf['advagg_async_generation'] = 0;
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
  elseif (!$is_dev && $drupal_seven && $all_ini['advagg_auto_configuration'] && (is_readable('modules/o_contrib_seven/advagg/advagg_bundler/advagg_bundler.module') ||
          is_readable('sites/all/modules/advagg/advagg_bundler/advagg_bundler.module'))) {
    $conf['advagg_bundler_active'] = 1;
    $conf['advagg_cache_level'] = 1;
    $conf['advagg_combine_css_media'] = 0;
    $conf['advagg_core_groups'] = 0;
    $conf['advagg_css_compressor'] = 2;
    $conf['advagg_css_inline_compressor'] = 2;
    $conf['advagg_css_inline_compress_if_not_cacheable'] = 1;
    $conf['advagg_enabled'] = 1;
    $conf['advagg_gzip'] = 1;
    $conf['advagg_ie_css_selector_limiter'] = 1;
    $conf['advagg_js_compressor'] = 3;
    $conf['advagg_js_compress_packer'] = 0;
    $conf['advagg_js_inline_compressor'] = 3;
    $conf['advagg_js_inline_compress_if_not_cacheable'] = 1;
    $conf['preprocess_css'] = 1;
    $conf['preprocess_js'] = 1;
  }

  if (!$is_dev && (is_readable('modules/o_contrib/httprl/httprl.module') || is_readable('modules/o_contrib_seven/httprl/httprl.module'))) {
    $conf['advagg_use_httprl'] = 1;
    $conf['httprl_background_callback'] = 1;
    $conf['httprl_connect_timeout'] = 3;
    $conf['httprl_dns_timeout'] = 3;
    $conf['httprl_global_timeout'] = "60";
    $conf['httprl_server_addr'] = "-1";
    $conf['httprl_timeout'] = "10";
    $conf['httprl_ttfb_timeout'] = "5";
    ### $conf['drupal_http_request_function'] = "httprl_override_core";
  }

  if (is_readable('modules/o_contrib/purge/purge.inc')) {
    $conf['purge_proxy_urls'] = "http://127.0.0.1:8888/purge-normal?purge_method=get http://127.0.0.1:8888/purge-mobile-tablet?purge_method=get http://127.0.0.1:8888/purge-mobile-smart?purge_method=get http://127.0.0.1:8888/purge-mobile-other?purge_method=get";
    if ($is_dev && !$is_backend) {
      header('X-Purge-Level: 6');
    }
  }
  elseif (is_readable('modules/o_contrib_seven/purge/purge.inc')) {
    $conf['expire_flush_node_terms'] = 0; // Disable this to avoid WSOD - see http://drupal.org/node/1151686#comment-5556544
    $conf['purge_proxy_urls'] = "http://127.0.0.1:8888/purge-normal?purge_method=get http://127.0.0.1:8888/purge-mobile-tablet?purge_method=get http://127.0.0.1:8888/purge-mobile-smart?purge_method=get http://127.0.0.1:8888/purge-mobile-other?purge_method=get";
    if ($is_dev && !$is_backend) {
      header('X-Purge-Level: 7');
    }
  }
  else {
    if ($is_dev && !$is_backend) {
      header('X-Purge-Level: none');
    }
  }

  if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) || isset($_SERVER['HTTPS'])) {
    $conf['https'] = TRUE;
    $request_type = ($_SERVER['HTTP_X_FORWARDED_PROTO'] == 'https' || $_SERVER['HTTPS'] == 'on') ? 'SSL' : 'NONSSL';
    if ($request_type == "SSL") { // we check for secure connection to set correct base_url
      $base_url = 'https://' . $_SERVER['HTTP_HOST'];
      if ($conf['install_profile'] != 'hostmaster') {
        $_SERVER['HTTPS'] = 'on';
        if ($drupal_seven || $drupal_eight) {
          ini_set('session.cookie_secure', TRUE);
          if ($is_dev && !$is_backend) {
            header('X-Cookie-Sec: YES');
          }
        }
      }
      if ($is_dev && !$is_backend) {
        header('X-Local-Proto: https');
      }
    }
    else {
      $base_url = 'http://' . $_SERVER['HTTP_HOST'];
    }
  }
  else {
    $base_url = 'http://' . $_SERVER['HTTP_HOST'];
  }

  if ($all_ini['server_name_cookie_domain']) {
    $domain = '.'. preg_replace('`^www.`', '', $_SERVER['SERVER_NAME']);
  }
  else {
    $domain = '.'. preg_replace('`^www.`', '', $_SERVER['HTTP_HOST']);
  }
  $domain = str_replace('..', '.', $domain);
  if (count(explode('.', $domain)) > 2 && !is_numeric(str_replace('.', '', $domain))) {
    @ini_set('session.cookie_domain', $domain);
    $cookie_domain = $domain;
    if (!$is_backend) {
      header("X-Cookie-Domain: " . $cookie_domain);
    }
  }

  $this_prefix = preg_replace('`^www.`', '', $_SERVER['SERVER_NAME']) . '_';
  if ($is_dev && !$is_backend) {
    header("X-Redis-Prefix: " . $this_prefix);
  }

  if (isset($_SERVER['REQUEST_TIME']) && isset($_SERVER['REMOTE_ADDR']) && isset($_SERVER['HTTP_USER_AGENT']) &&
      !preg_match("/^\/esi\//", $_SERVER['REQUEST_URI'])) {
    $identity = $_SERVER['REQUEST_TIME'] . $_SERVER['REMOTE_ADDR'] . $_SERVER['SERVER_NAME'] . $_SERVER['HTTP_USER_AGENT'];
    $identity = 'BD'. md5("$identity");
    if ($drupal_seven || $drupal_eight) {
      $conf['https'] = TRUE;
      $sess_prefix = ini_get('session.cookie_secure') ? 'SSESS' : 'SESS';
      $test_sess_name = $sess_prefix . substr(hash('sha256', $cookie_domain), 0, 32);
    }
    else {
      $test_sess_name = 'SESS'. md5($cookie_domain);
    }
    if (!isset($_COOKIE[$test_sess_name])) {
      if ($all_ini['speed_booster_anon_cache_ttl'] && preg_match("/^[0-9]{2,}$/", $all_ini['speed_booster_anon_cache_ttl'])) {
        if ($all_ini['speed_booster_anon_cache_ttl'] > 10) {
          $expire_in_seconds = $all_ini['speed_booster_anon_cache_ttl'];
          if (!$is_backend) {
            header('X-Limit-Booster:' . $all_ini['speed_booster_anon_cache_ttl']);
          }
        }
      }
    }
    if (!isset($_COOKIE[$test_sess_name])) {
      if (preg_match("/\/(?:node\/[0-9]+\/edit|node\/add)/", $_SERVER['REQUEST_URI'])) {
        if (!$all_ini['allow_anon_node_add'] && !$is_backend) {
          $deny_anon = TRUE;
          header("HTTP/1.1 301 Moved Permanently");
          header("Location: " . $base_url . "/");
          header("Connection: close");
          exit;
        }
      }
      if (preg_match("/^\/(?:[a-z]{2}\/)?(?:admin|logout|privatemsg|approve)/", $_SERVER['REQUEST_URI'])) {
        if (!$all_ini['disable_admin_dos_protection'] && !$is_backend) {
          $deny_anon = TRUE;
          header("HTTP/1.1 301 Moved Permanently");
          header("Location: " . $base_url . "/");
          header("Connection: close");
          exit;
        }
      }
    }
    // Prevent turning the feature server site into a spam machine
    // Disable self-registration also on hostmaster
    if ($conf['install_profile'] == 'feature_server' || $conf['install_profile'] == 'hostmaster') {
      $conf['user_register'] = 0; // Force "Only site administrators can create new user accounts"
    }
    if (!$known_bot && !$high_traffic && !$deny_anon) {
      if (preg_match("/^\/(?:[a-z]{2}\/)?(?:user|admin|cart|checkout|logout|privatemsg)/", $_SERVER['REQUEST_URI']) ||
          preg_match("/\/(?:node\/[0-9]+\/edit|node\/add|comment\/reply|approve|users|ajax_comments|commerce_currency_select)/", $_SERVER['REQUEST_URI']) ||
          preg_match("/(?:^dev\.|\.dev\.|\.devel\.)/", $_SERVER['HTTP_HOST'])) {
        if (!isset($_COOKIE['NoCacheID'])) {
          $lifetime = '15';
          setcookie('NoCacheID', 'NC' . $identity, $_SERVER['REQUEST_TIME'] + $lifetime, '/', $cookie_domain);
        }
        $expire_in_seconds = '1';
        if (!$is_backend) {
          header('X-Limit-Booster: 1');
        }
      }
      if (isset($_SERVER['REQUEST_URI']) && preg_match("/(?:x-progress-id|ahah|progress\/|autocomplete|ajax|batch|js\/.*)/i", $_SERVER['REQUEST_URI'])) {
        $expire_in_seconds = '0';
        if ($is_dev && !$is_backend) {
          header('X-Skip-Booster: AjaxRU');
        }
      }
      if (isset($_SERVER['QUERY_STRING']) && preg_match("/(?:x-progress-id|ahah|progress\/|autocomplete|ajax|batch|js\/.*)/i", $_SERVER['QUERY_STRING'])) {
        $expire_in_seconds = '0';
        if ($is_dev && !$is_backend) {
          header('X-Skip-Booster: AjaxQS');
        }
      }
      if (isset($_SERVER['REQUEST_METHOD']) && $_SERVER['REQUEST_METHOD'] == 'POST') {
        if (!isset($_COOKIE['NoCacheID'])) {
          $lifetime = '15';
          setcookie('NoCacheID', 'POST' . $identity, $_SERVER['REQUEST_TIME'] + $lifetime, '/', $cookie_domain);
        }
        $expire_in_seconds = '0';
        if ($is_dev && !$is_backend) {
          header('X-Skip-Booster: PostRM');
        }
      }
    }
    if ($known_bot) {
      if (!preg_match("/Pingdom/i", $_SERVER['HTTP_USER_AGENT'])) {
        $expire_in_seconds = '86400';
        if ($is_dev && !$is_backend) {
          header('X-Bot-Booster: 86400');
        }
      }
    }
    if ($conf['install_profile'] != 'hostmaster' && ($expire_in_seconds > -1) && !$is_backend) {
      header("X-Accel-Expires: " . $expire_in_seconds);
    }
  }
}

/**
 * Optional system level overrides
 */
if (is_readable('/data/conf/override.global.inc')) {
  require_once "/data/conf/override.global.inc";
}

// Use Redis caching and lock support only for d6 and d7 profiles
if ($redis_up && $use_redis && !$custom_cache) {
  $cache_backport = FALSE;
  $cache_redis = FALSE;
  if ($all_ini['redis_use_modern']) {
    $redis_dirname = 'redis_edge';
    if ($is_dev && !$is_backend) {
      header("X-Redis-Version-Is: Modern");
    }
    if ($all_ini['redis_flush_forced_mode']) {
      $conf['redis_flush_mode']             = 1; // Redis default is 0
      $conf['redis_flush_mode_cache_page']  = 2; // Redis default is 1
      $conf['redis_flush_mode_cache_block'] = 2; // Redis default is 1
      $conf['redis_flush_mode_cache_menu']  = 2; // Redis default is 0
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
    }
  }
  if (is_readable('modules/o_contrib/cache_backport/cache.inc')) {
    $cache_backport = TRUE;
    $cache_backport_path = 'modules/o_contrib/cache_backport/cache.inc';
    if ($is_dev && !$is_backend) {
      header("X-Redis-Cache-Backport-Is-Readable: " . $cache_backport_path);
    }
  }
  if (is_readable('modules/o_contrib_seven/' . $redis_dirname . '/redis.autoload.inc')) {
    $cache_redis = TRUE;
    $cache_backport = FALSE;
    $cache_redis_path = 'modules/o_contrib_seven/' . $redis_dirname . '/redis.autoload.inc';
    $cache_lock_path = 'modules/o_contrib_seven/' . $redis_dirname . '/redis.lock.inc';
    if ($is_dev && !$is_backend) {
      header("X-Redis-Autoload-Is-Readable: " . $cache_redis_path);
    }
  }
  elseif (is_readable('modules/o_contrib/' . $redis_dirname . '/redis.autoload.inc')) {
    $cache_redis = TRUE;
    $cache_redis_path = 'modules/o_contrib/' . $redis_dirname . '/redis.autoload.inc';
    $cache_lock_path = 'modules/o_contrib/' . $redis_dirname . '/redis.lock.inc';
    if ($is_dev && !$is_backend) {
      header("X-Redis-Autoload-Is-Readable: " . $cache_redis_path);
    }
  }
  if ($cache_redis) {
    if ($cache_backport) {
      $conf['cache_inc']                      = $cache_backport_path;
    }
    if ($all_ini['redis_use_modern'] && $all_ini['redis_lock_enable']) {
      $redis_lock = TRUE;
    }
    if (is_readable($cache_lock_path) && $redis_lock) {
      $conf['lock_inc']                       = $cache_lock_path;
      if ($is_dev && !$is_backend) {
        header("X-Redis-Lock-Is-Readable: " . $cache_lock_path);
      }
    }
    $conf['cache_backends'][]                 = $cache_redis_path;
    $conf['redis_client_interface']           = 'PhpRedis';
    $conf['redis_client_host']                = '127.0.0.1';
    $conf['redis_client_port']                = '6379';
    $conf['redis_client_password']            = 'isfoobared';
    $conf['cache_prefix']                     = $this_prefix;
    $conf['page_cache_invoke_hooks']          = TRUE;  // D7 == Do not use Aggressive Mode
    $conf['page_cache_without_database']      = FALSE; // D7 == Do not use Aggressive Mode
    $conf['page_cache_maximum_age']           = 0;     // D7 == max-age in the Cache-Control header (ignored by Speed Booster)
    $conf['page_cache_max_age']               = 0;     // D6 == max-age in the Cache-Control header (ignored by Speed Booster)
    $conf['cache_lifetime']                   = 0;     // D7 == BOA uses Speed Booster / Nginx micro-caching instead
    $conf['page_cache_lifetime']              = 0;     // D6 == BOA uses Speed Booster / Nginx micro-caching instead
    $conf['cache_default_class']              = 'Redis_Cache';
    $conf['cache_class_cache_form']           = 'DrupalDatabaseCache';
    if ($conf['install_profile'] == 'hostmaster' && !$all_ini['redis_use_modern']) {
      $conf['cache_class_cache']              = 'DrupalDatabaseCache';
    }
  }
}

/**
 * Drupal for Facebook (fb)
 *
 * Important:
 * Facebook client libraries will not work properly if arg_separator.output is not &
 * The default value is &amp;. Change this in settings.php. Make the value "&"
 * http://drupal.org/node/205476
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
 * New Relic - see: https://newrelic.com/docs/php/per-directory-settings#perdir-rollup
 * Support for background job borrowed from https://drupal.org/project/newrelic_drush_plugin
 */
if (extension_loaded('newrelic')) {
  ini_set('newrelic.framework', 'drupal');
  $this_instance = FALSE;
  if ($is_backend) {
    $context = drush_get_context();
    $uri = FALSE;
    if (isset($context['DRUSH_URI'])) {
      $uri = $context['DRUSH_URI'];
      $uri = str_replace('http://', '', $uri);
      $uri = str_replace('https://', '', $uri);
    }
    elseif (isset($context['DRUSH_DRUPAL_SITE'])) {
      $uri = $context['DRUSH_DRUPAL_SITE'];
    }
    if ($uri) {
      $this_instance = 'Site: ' . $uri;
      $root = FALSE;
      // Support Barracuda and Octopus naming convention
      if (isset($context['DRUSH_DRUPAL_CORE'])) {
        $root = $context['DRUSH_DRUPAL_CORE'];
      }
      elseif (isset($context['DRUSH_DRUPAL_ROOT'])) {
        $root = $context['DRUSH_DRUPAL_ROOT'];
      }
      if ($root) {
        $frags = explode("/", $root);
        if ($frags[1] == 'data') {
          $this_instance = 'Site: ' . $uri . ';AAA Octopus ' . $frags[3] . ';AAA All Instances';
        }
        elseif ($frags[2] == 'aegir') {
          $this_instance = 'Site: ' . $uri . ';AAA Barracuda Master;AAA All Instances';
        }
      }
      // Build drush command
      $drush_command = array_merge(array($command['command']), $command['arguments']);
      newrelic_add_custom_parameter('Drush command', implode(' ', $drush_command));
      newrelic_name_transaction(implode(' ', $drush_command));
      newrelic_background_job(TRUE);
    }
  }
  else {
    if (isset($_SERVER['DOCUMENT_ROOT']) && isset($_SERVER['SERVER_NAME'])) {
      $frags = explode("/", $_SERVER['DOCUMENT_ROOT']);
      if ($frags[1] == 'data') {
        $this_instance = 'Site: ' . $_SERVER['SERVER_NAME'] . ';AAA Octopus ' . $frags[3] . ';AAA All Instances';
      }
      elseif ($frags[2] == 'aegir') {
        $this_instance = 'Site: ' . $_SERVER['SERVER_NAME'] . ';AAA Barracuda Master;AAA All Instances';
      }
    }
  }
  if ($this_instance) {
    ini_set('newrelic.appname', $this_instance);
    newrelic_set_appname($this_instance);
  }
}

/**
 * Unset config arrays on non-dev URLs
 */
if (!$is_dev) {
  unset($boa_ini);
  unset($usr_plr_ini);
  unset($all_ini);
}
