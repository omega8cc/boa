<?php # override global settings.php

if (isset($_SERVER['HTTP_HOST']) && preg_match("/(?:domain\.com|another-domain\.com)/", $_SERVER['HTTP_HOST'])) {
  $use_cache = NO;  // disable Memcached + Redis cache for listed domains
}
