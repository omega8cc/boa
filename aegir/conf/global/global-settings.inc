<?php # global settings.php


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
  $config['system.cron']['threshold.autorun'] = FALSE;             // Disable poormanscron
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
        // This file, if exists, disables Redis on the fly!
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
      ini_set('opcache.revalidate_freq', '60');
      if (!$is_backend) {
        header("X-Opcache-Revalidate-Freq: 60");
      }
    }
    else {
      // Set sane default opcache TTL on non-dev sites
      ini_set('opcache.revalidate_freq', '10');
      if (!$is_backend) {
        header("X-Opcache-Revalidate-Freq: 10");
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
if ($all_ini['session_cookie_ttl']) {
  ini_set('session.cookie_lifetime', $all_ini['session_cookie_ttl']);
}


/**
 * Session Garbage Collector EOL settings
 *
 * Set session lifetime (in seconds), i.e. the time from the user's last visit
 * to the active session may be deleted by the session garbage collector. When
 * a session is deleted, authenticated users are logged out, and the contents
 * of the user's $_SESSION variable is discarded.
 */
if ($all_ini['session_gc_eol']) {
  ini_set('session.gc_maxlifetime', $all_ini['session_gc_eol']);
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
