<?php # global settings.php


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
  $ok = @touch($flag_path);
  return $ok ? TRUE : FALSE;
}

function _valkey_backoff_clear($flag_path) {
  if (is_file($flag_path)) {
    @unlink($flag_path);
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

      // Prefer unix socket if available and readable.
      if (!empty($valkey_socket_path)) {
        if (@is_readable($valkey_socket_path)) {
          $connected = $r->connect($valkey_socket_path);
        }
      }

      // Fallback to TCP if socket path not usable.
      if (!$connected) {
        $connected = $r->connect($valkey_host, $valkey_port, $connect_timeout_s);
      }

      if ($connected) {
        // Apply read timeout if supported by the loaded phpredis.
        if (defined('Redis::OPT_READ_TIMEOUT')) {
          $r->setOption(Redis::OPT_READ_TIMEOUT, $read_timeout_s);
        }

        // Authenticate if password file exists and has a non-empty secret.
        $need_auth = FALSE;
        $auth_pass = 'isfoobared';
        if (is_file($valkey_pass_file)) {
          $auth_pass = @file_get_contents($valkey_pass_file);
          if ($auth_pass !== FALSE) {
            $auth_pass = trim($auth_pass);
            if ($auth_pass !== '') {
              $need_auth = TRUE;
            }
          }
        }

        if ($need_auth) {
          $auth_ok = FALSE;
          try {
            $auth_ok = $r->auth($auth_pass);
          } catch (Exception $e) {
            $auth_ok = FALSE;
          }
          if (!$auth_ok) {
            $connected = FALSE;
          }
        }

        if ($connected) {
          // Final sanity: cheap ping.
          $pong_ok = FALSE;
          try {
            $pong = $r->ping();
            if (is_string($pong)) {
              if (stripos($pong, 'PONG') !== FALSE) {
                $pong_ok = TRUE;
              }
            } else {
              if ($pong === TRUE) {
                $pong_ok = TRUE;
              }
            }
          } catch (Exception $e) {
            $pong_ok = FALSE;
          }

          if ($pong_ok) {
            $valkey_up = TRUE;
            _valkey_backoff_clear($flag_path);
          } else {
            $valkey_up = FALSE;
            _valkey_backoff_touch($flag_path);
          }
        } else {
          $valkey_up = FALSE;
          _valkey_backoff_touch($flag_path);
        }

        // Clean up the connection object explicitly for older PHP.
        try {
          if ($valkey_up) {
            $r->close();
          }
        } catch (Exception $e) {
          // ignore
        }
      } else {
        $valkey_up = FALSE;
        _valkey_backoff_touch($flag_path);
      }
    } else {
      // phpredis extension not available.
      $valkey_up = FALSE;
      _valkey_backoff_touch($flag_path);
    }
  } else {
    // Within backoff window; assume down to avoid blocking page loads.
    $valkey_up = FALSE;
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
