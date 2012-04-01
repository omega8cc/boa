<?php # override global settings.php

// This file should be created as /data/conf/override.global.inc.

// Disable Redis cache for listed domains.
if (isset($_SERVER['HTTP_HOST']) && preg_match("/(?:domain\.com|another-domain\.com)/", $_SERVER['HTTP_HOST'])) {
  $use_cache = FALSE;
}

// Disable Redis cache for anonymous visitors if this causes wsod
// for listed domains, as it is now enabled by default.
// The code below will make it working for logged in users only, as before.
if (isset($_SERVER['HTTP_HOST']) && preg_match("/(?:domain\.com|another-domain\.com)/", $_SERVER['HTTP_HOST'])) {
  if (isset($_COOKIE[$test_sess_name]) && isset($_SERVER['HTTP_COOKIE']) &&
      preg_match("/(?:OctopusNoCacheID)/", $_SERVER['HTTP_COOKIE'])) {
    $use_cache = TRUE;
  }
  else {
    $use_cache = FALSE;
  }
}

// Kind of core version agnostic, securepages module
// for proper HTTP/HTTPS redirects.
if (isset($_SERVER['HTTP_HOST']) && preg_match("/(?:domain\.com|another-domain\.com)/", $_SERVER['HTTP_HOST']) &&
    isset($_SERVER['REQUEST_URI']) && isset($_SERVER['HTTP_USER_AGENT'])) {
  $request_type = ($_SERVER['HTTP_X_FORWARDED_PROTO'] == 'https') ? 'SSL' : 'NONSSL';
  $conf['https'] = TRUE;
  if (preg_match("/^\/(?:cart.*|admin.*|donate.*|civicrm.*|node\/add.*|node\/.*\/edit)$/", $_SERVER['REQUEST_URI']) ||
      preg_match("/^\/(?:user.*|user\/.*\/edit.*|user\/reset.*|user\/register.*|user\/logout|user\/password|user\/login)$/", $_SERVER['REQUEST_URI'])) {
    $base_url = 'https://' . $_SERVER['HTTP_HOST'];
    if ($request_type != "SSL") {
      header('X-Accel-Expires: 1');
      // Note: never use header('X-Accel-Expires: 0'); to disable Speed Booster completely.
      // You always want that one second or you will be vulnerable to DoS attacks.
      header("HTTP/1.1 301 Moved Permanently");
      header("Location: https://" . $_SERVER['HTTP_HOST'] . $_SERVER['REQUEST_URI']);
    }
  }
  else {
    $base_url = 'http://' . $_SERVER['HTTP_HOST'];
    if ($request_type == "SSL" && !preg_match("/(?:x-progress-id|ahah|filefield_nginx_progress\/*|autocomplete|ajax|batch|js\/.*)/", $_SERVER['REQUEST_URI'])) {
      header('X-Accel-Expires: 1');
      // Note: never use header('X-Accel-Expires: 0'); to disable Speed Booster completely.
      // You always want that one second or you will be vulnerable to DoS attacks.
      header("HTTP/1.1 301 Moved Permanently");
      header("Location: http://" . $_SERVER['HTTP_HOST'] . $_SERVER['REQUEST_URI']);
    }
  }
}
