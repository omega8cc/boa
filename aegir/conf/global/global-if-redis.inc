<?php # global settings.php


if ($drupal_core >= 6) {
  $use_redis = TRUE;
}

if (isset($_SERVER['SERVER_NAME']) && $all_ini['redis_cache_disable']) {
  $use_redis = FALSE;
}

if (!$is_bot && isset($_SERVER['REQUEST_URI']) &&
    preg_match("/noredis=1/", $_SERVER['REQUEST_URI'])) {
  $use_redis = FALSE;
}

if ($use_redis && !$is_install && !$custom_cache) {
  $redis = new Redis();
  $redis->connect('127.0.0.1', 6379);
  if ($redis->isConnected()) {
    $redis->auth('isfoobared');
    $response = $redis->ping('PONG');
    if ($is_dev && !$is_backend) {
      header("X-Redis-Response: " . $response);
    }
    if (preg_match("/PONG/", $response)) {
      $redis_up = TRUE;
    }
    else {
      if ($is_dev && !$is_backend) {
        header("X-Redis-Up: " . $redis_up);
      }
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

if ($is_install) {
  $use_redis = FALSE;
}
