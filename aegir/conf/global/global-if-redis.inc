<?php # global settings.php


if ($drupal_core >= 6) {
  $use_valkey = TRUE;
}

if (isset($_SERVER['SERVER_NAME'])) {
  if ($all_ini['valkey_cache_disable'] || $all_ini['redis_cache_disable']) {
    $use_valkey = FALSE;
  }
}

if (!$is_bot && isset($_SERVER['REQUEST_URI']) &&
    preg_match("/noredis=1/", $_SERVER['REQUEST_URI'])) {
  $use_valkey = FALSE;
}

if ($use_valkey && !$is_install && !$custom_cache) {
  $redis = new Redis();
  $redis->connect('127.0.0.1', 6379);
  if ($redis->isConnected()) {
    $redis->auth('isfoobared');
    $response = $redis->ping('PONG');
    if ($is_dev && !$is_backend) {
      header("X-Valkey-Response: " . $response);
    }
    if (preg_match("/PONG/", $response)) {
      $valkey_up = TRUE;
    }
    else {
      if ($is_dev && !$is_backend) {
        header("X-Valkey-Up: " . $valkey_up);
      }
    }
    $redis->close();
  }
}

if ($valkey_up && $use_valkey) {
  if ($is_dev && !$is_backend) {
    header('X-Allow-Valkey: YES');
  }
}
else {
  if ($is_dev && !$is_backend) {
    header('X-Allow-Valkey: NO');
  }
}

if ($is_install) {
  $use_valkey = FALSE;
}
