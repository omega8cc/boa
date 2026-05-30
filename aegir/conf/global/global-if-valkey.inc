<?php # global settings.php


/* ---------------- Feature switch -------------------------------------- */
if ($drupal_core >= 6) {
  $use_valkey = TRUE;
}

if (isset($_SERVER['SERVER_NAME'])) {
  /* Honour redis_cache_disable only. The legacy valkey_cache_disable key was
   * undocumented, never shipped in $boa_ini defaults (so it raised an
   * undefined-key warning) and merely duplicated this redis-namespace flag. */
  if (isset($all_ini['redis_cache_disable']) && $all_ini['redis_cache_disable']) {
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

/* ---------------- Timeouts & backoff (ini-tunable, was hardcoded) ------ */
/* INI variables use the stable "redis_" namespace even on Valkey servers. */
$connect_timeout_s  = (isset($all_ini['redis_connect_timeout']) && $all_ini['redis_connect_timeout'] !== '') ? (float) $all_ini['redis_connect_timeout'] : 0.7;
$read_timeout_s     = (isset($all_ini['redis_read_timeout'])    && $all_ini['redis_read_timeout']    !== '') ? (float) $all_ini['redis_read_timeout']    : 0.7;
$backoff_ttl_s      = (isset($all_ini['redis_backoff_ttl'])     && $all_ini['redis_backoff_ttl']     !== '') ? (int)   $all_ini['redis_backoff_ttl']     : 15;
$probe_retry        = isset($all_ini['redis_probe_retry'])            ? (bool) $all_ini['redis_probe_retry']            : TRUE;
$flush_apcu_recov   = isset($all_ini['redis_flush_apcu_on_recovery']) ? (bool) $all_ini['redis_flush_apcu_on_recovery'] : TRUE;
$cache_dbg_hdr      = isset($all_ini['redis_debug_header'])           ? (bool) $all_ini['redis_debug_header']           : FALSE;
$flag_dir_run       = '/var/tmp/fpm';
$flag_file_fallback = '/data/conf/arch/valkey.disabled.flag'; // fallback

/* ---------------- Optional probe debug log (namespace: valkey) --------- */
/* $redis_debug_log is a real, non-empty default path. Because everything in
 * global/ is overwritten on every BOA upgrade, the path is baked in here
 * rather than hand-edited per server. Whether anything is actually WRITTEN to
 * it is a separate, two-stage activation gate so there is NO extra disk I/O
 * for anyone unless explicitly armed:
 *   1. INI 'redis_debug' must be TRUE (set in the platform/site control ini).
 *      This is the ONLY thing evaluated by default; when FALSE the && below
 *      short-circuits and we do zero extra filesystem work here.
 *   2. Only then is the control flag file checked; logging activates only
 *      while that flag exists. Toggle live, with no ini edit or redeploy:
 *        touch /data/conf/valkey.debug.flag   (start logging)
 *        rm    /data/conf/valkey.debug.flag   (stop logging)
 * _valkey_dbg_write() is a no-op whenever $redis_debug_on is FALSE. */
$redis_debug_log = '/var/tmp/fpm/valkey-fallback.log';
$redis_debug     = isset($all_ini['redis_debug']) ? (bool) $all_ini['redis_debug'] : FALSE;
$redis_debug_on  = ($redis_debug && is_file('/data/conf/valkey.debug.flag'));

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

function _valkey_dbg_write($enabled, $log_path, $line) {
  if ($enabled && !empty($log_path)) {
    $msg = date('c').' '.$line."\n";
    @file_put_contents($log_path, $msg, FILE_APPEND);
  }
}

/* One full connect+auth+ping attempt. Returns TRUE on healthy PONG.
 * $reason is set by-ref to 'ok' or a short failure code. Keeps each
 * attempt self-contained so the caller can retry cheaply before
 * tripping the shared backoff flag. */
function _valkey_probe_once($socket_path, $host, $port, $pass, $connect_timeout_s, $read_timeout_s, &$reason) {
  $reason = 'init';
  if (!class_exists('Redis')) {
    $reason = 'no-phpredis';
    return FALSE;
  }
  $r = new Redis();
  $connected = FALSE;
  // Try socket first.
  if (!empty($socket_path) && @is_readable($socket_path)) {
    try {
      $connected = $r->connect($socket_path);
    } catch (Exception $e) {
      $connected = FALSE;
      $reason = 'connect-socket-exception';
    }
  }
  // Fallback to TCP.
  if (!$connected) {
    try {
      $connected = $r->connect($host, $port, $connect_timeout_s);
    } catch (Exception $e) {
      $connected = FALSE;
      $reason = 'connect-tcp-exception';
    }
  }
  if (!$connected) {
    if ($reason === 'init') {
      $reason = 'connect-failed';
    }
    return FALSE;
  }
  if (defined('Redis::OPT_READ_TIMEOUT')) {
    $r->setOption(Redis::OPT_READ_TIMEOUT, $read_timeout_s);
  }
  // Authenticate if a password is configured.
  if ($pass !== '') {
    try {
      if (!$r->auth($pass)) {
        try { $r->close(); } catch (Exception $e) {}
        $reason = 'auth-failed';
        return FALSE;
      }
    } catch (Exception $e) {
      try { $r->close(); } catch (Exception $e2) {}
      $reason = 'auth-exception';
      return FALSE;
    }
  }
  // Verify ping.
  $ok = FALSE;
  try {
    $pong = $r->ping();
    if ((is_string($pong) && stripos($pong, 'PONG') !== FALSE) || $pong === TRUE) {
      $ok = TRUE;
    } else {
      $reason = 'ping-not-ok';
    }
  } catch (Exception $e) {
    $reason = 'ping-exception';
  }
  try { $r->close(); } catch (Exception $e) {}
  if ($ok) {
    $reason = 'ok';
  }
  return $ok;
}

/* ------------------- Probe Valkey once with guard --------------------- */
$flag_path = _valkey_backoff_flag_path($flag_dir_run, $flag_file_fallback);
$flag_existed = is_file($flag_path);
$skip_probe = _valkey_backoff_is_active($flag_path, $backoff_ttl_s);
$last_reason = 'init';

if ($use_valkey) {
  if (!$skip_probe) {
    // Resolve password (file overrides hardcoded fallback).
    $auth_pass = 'isfoobared';
    if (is_file($valkey_pass_file)) {
      $auth_pass = trim((string) @file_get_contents($valkey_pass_file));
    }

    // One probe, plus a single cheap retry before tripping the shared
    // backoff. A single 0.x s blip (GC pause, socket backlog) should not
    // drop the whole worker pool into DB-cache mode for the backoff window.
    $attempts = $probe_retry ? 2 : 1;
    for ($i = 0; $i < $attempts; $i++) {
      $valkey_up = _valkey_probe_once($valkey_socket_path, $valkey_host, $valkey_port, $auth_pass, $connect_timeout_s, $read_timeout_s, $last_reason);
      if ($valkey_up) {
        break;
      }
      if ($last_reason === 'no-phpredis') {
        break; // retrying cannot help
      }
    }

    if ($valkey_up) {
      // Recovery: we were flagged down and are now up again. Flush the local
      // APCu so any stale ChainedFast front-layer entries written (or missed)
      // during the degraded window are discarded and rebuilt from the
      // consistent Valkey backend. This is the key fix for "config changes
      // not applied" persisting after a transient blip.
      //
      // Elect a SINGLE flusher per recovery: claim the backoff flag with an
      // atomic rename() so exactly one worker runs the pool-wide, lock-taking
      // apcu_clear_cache(); every other worker simply ensures the flag is
      // gone. Without this, many workers can pass the $flag_existed gate at
      // the same recovery instant and each fire a full-segment clear, all
      // contending for the APCu write lock just as the pool is recovering.
      // rename() is atomic on POSIX (only one caller can move the flag) and is
      // not in BOA's disable_functions list. A '.flushing' temp left behind by
      // a crashed winner is harmless: backoff logic only looks at $flag_path,
      // and the next rename() simply overwrites it.
      $flush_claimed = FALSE;
      if ($flag_existed && $flush_apcu_recov) {
        $claim_path = $flag_path . '.flushing';
        $flush_claimed = @rename($flag_path, $claim_path);
      }
      if ($flush_claimed) {
        if (function_exists('apcu_clear_cache')) {
          @apcu_clear_cache();
          _valkey_dbg_write($redis_debug_on, $redis_debug_log, 'VALKEY RECOVERY action=apcu_clear winner=1 flag='.$flag_path);
        }
        @unlink($claim_path);
      } else {
        // Lost the election, flushing disabled, or no flag was set: just make
        // sure the backoff flag is cleared.
        _valkey_backoff_clear($flag_path);
      }
      _valkey_dbg_write($redis_debug_on, $redis_debug_log, 'VALKEY UP action=clear flag='.$flag_path.' reason=ok');
    } else {
      _valkey_backoff_touch($flag_path);
      _valkey_dbg_write($redis_debug_on, $redis_debug_log, 'VALKEY DOWN action=touch flag='.$flag_path.' reason='.(string) $last_reason);
    }
  } else {
    $valkey_up = FALSE;
    $last_reason = 'backoff-active';
    _valkey_dbg_write($redis_debug_on, $redis_debug_log, 'VALKEY SKIP reason=backoff-active flag='.$flag_path);
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

/* Always-on, non-sensitive cache state header for production debugging.
 * Gated by the redis_debug_header ini flag (default FALSE; enable per-site
 * or per-platform while investigating, disable again afterwards).
 * Neutral X-Cache-* prefix so it reads identically on Redis or Valkey.
 * Reveals only a coarse state word - never the password or topology. */
if ($cache_dbg_hdr && empty($is_backend) && !headers_sent()) {
  $vk_state = 'disabled';
  if ($use_valkey) {
    if ($valkey_up) {
      $vk_state = 'up';
    } elseif ($skip_probe) {
      $vk_state = 'backoff';
    } elseif ($last_reason === 'no-phpredis') {
      $vk_state = 'nophpredis';
    } else {
      $vk_state = 'down';
    }
  }
  header('X-Cache-State: ' . $vk_state);
  header('X-Cache-Reason: ' . (string) $last_reason);
}

if (!empty($is_install)) {
  $use_valkey = FALSE;
}
