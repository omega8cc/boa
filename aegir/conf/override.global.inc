<?php # override global settings.php

// This file should be created as /data/conf/override.global.inc.


// Disable Memcached + Redis cache for listed domains.
if (isset($_SERVER['HTTP_HOST']) && preg_match("/(?:domain\.com|another-domain\.com)/", $_SERVER['HTTP_HOST'])) {
  $use_cache = 'NO';
}

// Deny known search bots on dev subdomains.
if (isset($_SERVER['HTTP_HOST']) && isset($_SERVER['HTTP_USER_AGENT']) &&
    preg_match("/dev/", $_SERVER['HTTP_HOST']) &&
    preg_match("/(?:crawl|google|yahoo|spider|bot|tracker|click|parser)/i", $_SERVER['HTTP_USER_AGENT'])) {

  header('X-Accel-Expires: 0');
  header("HTTP/1.1 301 Moved Permanently");
  header("Location: http://dev.null");
}

// Disable Memcached + Redis cache for anonymous visitors if this causes wsod
// for listed domains, as it is now enabled by default.
// The code below will make it working for logged in users only, as before.
if (isset($_SERVER['HTTP_HOST']) && preg_match("/(?:domain\.com|another-domain\.com)/", $_SERVER['HTTP_HOST'])) {
  if (isset($_COOKIE[$test_sess_name]) && isset($_SERVER['HTTP_COOKIE']) &&
      preg_match("/(?:OctopusNoCacheID)/", $_SERVER['HTTP_COOKIE'])) {
    $use_cache = 'YES';
  }
  else {
    $use_cache = 'NO';
  }
}

// Kind of core version agnostic, securepages module
// for proper HTTP/HTTPS redirects.
if (isset($_SERVER['HTTP_HOST']) && preg_match("/(?:domain\.com|another-domain\.com)/", $_SERVER['HTTP_HOST']) &&
    isset($_SERVER['REQUEST_URI']) && isset($_SERVER['HTTP_USER_AGENT'])) {
  $request_type = ($_SERVER['HTTP_X_FORWARDED_PROTO'] == 'https') ? 'SSL' : 'NONSSL';
  $conf['https'] = TRUE;
  if (preg_match("/^\/(?:cart.*|admin.*|user|user\/.*\/edit.*|user\/reset.*|user\/register|user\/logout|user\/password)$/", $_SERVER['REQUEST_URI'])) {
    $base_url = 'https://' . $_SERVER['HTTP_HOST'];
    if ($request_type != "SSL") {
      header('X-Accel-Expires: 0');
      header("HTTP/1.1 301 Moved Permanently");
      header("Location: https://" . $_SERVER['HTTP_HOST'] . $_SERVER['REQUEST_URI']);
    }
  }
  else {
    $base_url = 'http://' . $_SERVER['HTTP_HOST'];
    if ($request_type == "SSL" && !preg_match("/(?:autocomplete|ajax|batch|js\/.*)/", $_SERVER['REQUEST_URI'])) {
      header('X-Accel-Expires: 0');
      header("HTTP/1.1 301 Moved Permanently");
      header("Location: http://" . $_SERVER['HTTP_HOST'] . $_SERVER['REQUEST_URI']);
    }
  }
}
