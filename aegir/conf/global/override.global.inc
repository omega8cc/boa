<?php # override global settings.php

// This file should be created as /data/conf/override.global.inc.

// Kind of core version agnostic, securepages module
// for proper HTTP/HTTPS redirects.
if (isset($_SERVER['HTTP_HOST']) && preg_match("/(?:domain\.com|another-domain\.com)/", $_SERVER['HTTP_HOST']) &&
    isset($_SERVER['REQUEST_URI']) && isset($_SERVER['HTTP_USER_AGENT'])) {
  $request_type = ($_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') ? 'SSL' : 'NONSSL';
  $conf['https'] = TRUE;
  if (preg_match("/^\/(?:[a-z]{2}\/)?(?:cart.*|checkout.*|admin.*|donate.*|civicrm.*|node\/add.*|node\/.*\/edit)$/", $_SERVER['REQUEST_URI']) ||
      preg_match("/^\/(?:user.*|user\/.*\/edit.*|user\/reset.*|user\/register.*|user\/logout|user\/password|user\/login)$/", $_SERVER['REQUEST_URI'])) {
    $base_url = 'https://' . $_SERVER['HTTP_HOST'];
    if ($request_type !== "SSL") {
      header('X-Accel-Expires: 1');
      // Note: never use header('X-Accel-Expires: 0'); to disable Speed Booster completely.
      // You always want that one second or you will be vulnerable to DoS attacks.
      header("HTTP/1.1 301 Moved Permanently");
      header("Location: https://" . $_SERVER['HTTP_HOST'] . $_SERVER['REQUEST_URI']);
      header("Connection: close");
      exit;
    }
  }
  else {
    $base_url = 'http://' . $_SERVER['HTTP_HOST'];
    if ($request_type === "SSL" && !preg_match("/(?:x-progress-id|ahah|filefield_nginx_progress\/*|tinybrowser|f?ckeditor|tinymce|flowplayer|jwplayer|videomanager|autocomplete|ajax|batch|js\/.*)/", $_SERVER['REQUEST_URI'])) {
      header('X-Accel-Expires: 1');
      // Note: never use header('X-Accel-Expires: 0'); to disable Speed Booster completely.
      // You always want that one second or you will be vulnerable to DoS attacks.
      header("HTTP/1.1 301 Moved Permanently");
      header("Location: http://" . $_SERVER['HTTP_HOST'] . $_SERVER['REQUEST_URI']);
      header("Connection: close");
      exit;
    }
  }
}

$custom_cache = FALSE; // When set to TRUE in the /data/conf/override.global.inc file,
                       // it will disable default Redis configuration.

$custom_fb    = FALSE; // When set to TRUE in the /data/conf/override.global.inc file,
                       // it will disable default Drupal for Facebook (fb) configuration.

$custom_da    = FALSE; // When set to TRUE in the /data/conf/override.global.inc file,
                       // it will disable default Domain Access configuration,
                       // so you can define your own, custom configuration in the included below
                       // /data/conf/override.global.inc file. NOTE: if set to TRUE, then you
                       // must set to TRUE also $custom_cache and copy all its logic in your
                       // /data/conf/override.global.inc file, because Domain Access must be included
                       // *after* any cache-related settings to work properly.


/**
 * Custom Speed Booster TTL override, for example to force caching
 * on HTTPS-only site, where otherwise default TTL is just 1 second
 */
if (isset($_COOKIE[$test_sess_name])) {
  // Custom forced Speed Booster cache for logged in users
  $expire_in_seconds = 300;
}
else {
  // Custom forced Speed Booster cache for anonymous visitors
  $expire_in_seconds = 3600;
}
header("X-Accel-Expires: " . $expire_in_seconds);
