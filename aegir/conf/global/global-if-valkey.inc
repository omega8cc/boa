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

/* ---------------- Optional debug log ---------------------------------- */
// Set to an absolute path to enable lightweight probe logging.
// Example: '/data/conf/arch/log/valkey-fallback.log'
$redis_debug_log    = '';

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
  @touch($flag_path);
}

function _valkey_backoff_clear($flag_path) {
  if (is_file($flag_path)) {
    @unlink($flag_path);
  }
}

function _valkey_dbg_write($log_path, $line) {
  if (!empty($log_path)) {
    $msg = date('c').' '.$line."\n";
    @file_put_contents($log_path, $msg, FILE_APPEND);
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
      $last_reason = 'init';

      // Try socket first.
      if (!empty($valkey_socket_path) && @is_readable($valkey_socket_path)) {
        try {
          $connected = $r->connect($valkey_socket_path);
        } catch (Exception $e) {
          $connected = FALSE;
          $last_reason = 'connect-socket-exception';
        }
      }

      // Fallback to TCP.
      if (!$connected) {
        try {
          $connected = $r->connect($valkey_host, $valkey_port, $connect_timeout_s);
        } catch (Exception $e) {
          $connected = FALSE;
          $last_reason = 'connect-tcp-exception';
        }
      }

      if ($connected) {
        if (defined('Redis::OPT_READ_TIMEOUT')) {
          $r->setOption(Redis::OPT_READ_TIMEOUT, $read_timeout_s);
        }

        // Authenticate if password file exists.
        $auth_pass = 'isfoobared';
        if (is_file($valkey_pass_file)) {
          $auth_pass = trim((string) @file_get_contents($valkey_pass_file));
        }
        if ($auth_pass !== '') {
          try {
            if (!$r->auth($auth_pass)) {
              $connected = FALSE;
              $last_reason = 'auth-failed';
            }
          } catch (Exception $e) {
            $connected = FALSE;
            $last_reason = 'auth-exception';
          }
        }

        // Verify ping.
        if ($connected) {
          try {
            $pong = $r->ping();
            if ((is_string($pong) && stripos($pong, 'PONG') !== FALSE) || $pong === TRUE) {
              $valkey_up = TRUE;
            } else {
              $valkey_up = FALSE;
              $last_reason = 'ping-not-ok';
            }
          } catch (Exception $e) {
            $valkey_up = FALSE;
            $last_reason = 'ping-exception';
          }
        }

        if ($valkey_up) {
          _valkey_backoff_clear($flag_path);
          _valkey_dbg_write($redis_debug_log, 'VALKEY UP action=clear flag='.$flag_path.' reason=ok');
        } else {
          _valkey_backoff_touch($flag_path);
          _valkey_dbg_write($redis_debug_log, 'VALKEY DOWN action=touch flag='.$flag_path.' reason='.(string) $last_reason);
        }

        try {
          $r->close();
        } catch (Exception $e) {
          // ignore
        }
      } else {
        _valkey_backoff_touch($flag_path);
        _valkey_dbg_write($redis_debug_log, 'VALKEY DOWN action=touch flag='.$flag_path.' reason='.(string) $last_reason);
      }
    } else {
      // phpredis extension not available.
      $valkey_up = FALSE;
      _valkey_backoff_touch($flag_path);
      _valkey_dbg_write($redis_debug_log, 'VALKEY DOWN action=touch flag='.$flag_path.' reason=no-phpredis');
    }
  } else {
    $valkey_up = FALSE;
    _valkey_dbg_write($redis_debug_log, 'VALKEY SKIP reason=backoff-active flag='.$flag_path);
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
