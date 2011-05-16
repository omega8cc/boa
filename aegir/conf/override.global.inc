<?php # override global settings.php

// this file should be created as /data/conf/override.global.inc


// disable Memcached + Redis cache for listed domains
if (isset($_SERVER['HTTP_HOST']) && preg_match("/(?:domain\.com|another-domain\.com)/", $_SERVER['HTTP_HOST'])) {
  $use_cache = 'NO';
}

// deny known search bots on dev subdomains
if (isset($_SERVER['HTTP_HOST']) && isset($_SERVER['HTTP_USER_AGENT']) &&
    preg_match("/dev/", $_SERVER['HTTP_HOST']) &&
    preg_match("/(?:crawl|google|yahoo|spider|bot|tracker|click|parser)/i", $_SERVER['HTTP_USER_AGENT'])) {

  header("HTTP/1.1 301 Moved Permanently");
  header("Location: http://dev.null");
}
