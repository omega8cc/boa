<?php # global settings.php


/* ---------------- Feature switch -------------------------------------- */
if ($drupal_core >= 6 || !empty($backdropcms)) {
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
 * _valkey_dbg_write() is a no-op whenever $redis_debug_on is FALSE.
 * Each writing user logs to a file of this name in its own directory beside
 * it, named with its uid: valkey-fallback.<uid>/valkey-fallback.log (see
 * _valkey_dbg_write()). */
$redis_debug_log = '/var/tmp/fpm/valkey-fallback.log';
$redis_debug     = isset($all_ini['redis_debug']) ? (bool) $all_ini['redis_debug'] : FALSE;
$redis_debug_on  = ($redis_debug && is_file('/data/conf/valkey.debug.flag'));

/* ---------------- Helpers (filesystem only) ---------------------------- */
/* The flag is SHARED by every FPM pool on the box and by the CLI, which all
 * run as different users. /var/tmp/fpm is sticky (1777), and in a sticky
 * directory only the owner of a file can rename() or unlink() it: a flag
 * armed by one pool could then never be consumed by another pool's
 * recovery, so the pool-wide APCu flush and the clear happened only for the
 * pool that armed it. The flag therefore lives in its own, non-sticky, 0777
 * subdirectory. There the kernel's link protections do not apply, so
 * nothing here ever follows a link: the directory is root's own (made and
 * kept by root, used only while it and its sticky parent are real
 * root-owned directories), the flag is read through lstat(), refreshed by
 * renaming a freshly created file over it (rename replaces a link and never
 * follows it) and removed by unlink (which removes a link itself). */
function _valkey_backoff_flag_path($flag_dir_run, $fallback) {
  $path = $fallback;
  $dir = rtrim($flag_dir_run, '/');
  $sub = $dir.'/valkey';
  $pst = @lstat($dir);
  $st = @lstat($sub);
  if (is_array($pst) && ($pst['mode'] & 0170000) === 0040000
      && $pst['uid'] === 0 && ($pst['mode'] & 01000)
      && is_array($st) && ($st['mode'] & 0170000) === 0040000
      && $st['uid'] === 0 && is_writable($sub)) {
    $path = $sub.'/disabled.flag';
  }
  return $path;
}

/* The flag's mtime, or FALSE when there is no flag: absent, a link or
 * anything else that is not a regular file. */
function _valkey_backoff_mtime($flag_path) {
  $st = @lstat($flag_path);
  if (!is_array($st) || ($st['mode'] & 0170000) !== 0100000) {
    return FALSE;
  }
  return $st['mtime'];
}

function _valkey_backoff_is_active($flag_path, $ttl) {
  $active = FALSE;
  $mtime = _valkey_backoff_mtime($flag_path);
  if ($mtime !== FALSE) {
    $age = time() - $mtime;
    if ($age >= 0 && $age < $ttl) {
      $active = TRUE;
    }
  }
  return $active;
}

/* A new file is made under a random name, which nobody else can have made
 * first (fopen 'x' alone would not refuse a link already there: PHP
 * resolves it before the open), then renamed over the flag: the flag is
 * fresh, and no pool needs write access to another pool's file. */
function _valkey_backoff_touch($flag_path) {
  $tmp = $flag_path.'.'.md5(uniqid(mt_rand(), TRUE));
  $fh = @fopen($tmp, 'x');
  if ($fh === FALSE) {
    return;
  }
  fclose($fh);
  if (!@rename($tmp, $flag_path)) {
    @unlink($tmp);
  }
}

function _valkey_backoff_clear($flag_path) {
  @unlink($flag_path);
}

/* One log per writing user, in a directory of its own. Every pool and the
 * CLI run as different users, and in the sticky /var/tmp/fpm
 * (fs.protected_regular=2) one shared log made by one of them refused every
 * other user's append. No name another user can make is ever opened: PHP
 * resolves a link in a path itself before the open, so neither fopen 'x'
 * nor fs.protected_symlinks stops it following a link planted there.
 * mkdir() never follows a link; in a real, root-owned, sticky parent nobody
 * else can rename or replace this user's directory, and in the directory
 * (0700) nobody else can make an entry, so the log is opened only while
 * lstat() shows the directory as this user's own. The uid comes from
 * posix_geteuid(): getmyuid() is in the pool disable_functions and names
 * the script's owner, not the process. */
function _valkey_dbg_write($enabled, $log_path, $line) {
  if (!$enabled || empty($log_path) || !function_exists('posix_geteuid')) {
    return;
  }
  $pst = @lstat(dirname($log_path));
  if (!is_array($pst) || ($pst['mode'] & 0170000) !== 0040000
      || $pst['uid'] !== 0 || !($pst['mode'] & 01000)) {
    return;
  }
  $uid = posix_geteuid();
  $dir = preg_replace('/\.log$/', '', $log_path).'.'.$uid;
  $st = @lstat($dir);
  if (!is_array($st)) {
    @mkdir($dir, 0700);
    $st = @lstat($dir);
  }
  if (!is_array($st) || ($st['mode'] & 0170000) !== 0040000
      || $st['uid'] !== $uid || ($st['mode'] & 0022)) {
    return;
  }
  $path = $dir.'/'.basename($log_path);
  $fst = @lstat($path);
  if (is_array($fst) && ($fst['mode'] & 0170000) !== 0100000) {
    return;
  }
  @file_put_contents($path, date('c').' '.$line."\n", FILE_APPEND);
}

/* One full connect+auth+ping attempt. Returns TRUE on healthy PONG.
 * $reason is set by-ref to 'ok' or a short failure code. Keeps each
 * attempt self-contained so the caller can retry cheaply before
 * tripping the shared backoff flag. */
function _valkey_probe_once($socket_path, $host, $port, $pass, $connect_timeout_s, $read_timeout_s, &$reason, &$transport = NULL) {
  $reason = 'init';
  $transport = FALSE;
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
    if ($connected) {
      $transport = 'socket';
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
    if ($connected) {
      $transport = 'tcp';
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
  // Authenticate if a password is configured. On any failure the object is
  // simply dropped: close() sends QUIT and waits for the reply, so on a
  // server that accepted the connection but answers nothing it costs a
  // second full read timeout; the destructor closes the socket without one.
  if ($pass !== '') {
    try {
      if (!$r->auth($pass)) {
        $reason = 'auth-failed';
        return FALSE;
      }
    } catch (Exception $e) {
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
  if ($ok) {
    // A server that just answered PONG answers QUIT at once; only then is
    // an explicit close() free (see the auth block above).
    try { $r->close(); } catch (Exception $e) {}
    $reason = 'ok';
  }
  return $ok;
}

/* ---------------- Outage windows --------------------------------------- */
/* While Valkey cannot be reached a site runs on its database cache, so two
 * caches with separate tag counters take turns: what a request changes on the
 * database never reaches Valkey, and what changes while Valkey is up never
 * reaches the database cache. Each turn on the database is a window, recorded
 * beside the backoff flag in two files per scope: win.<scope>.open holds the
 * id of the window last opened ("<start microtime>-<md5>"), win.<scope>.closed
 * the id of the last one cleared from Valkey; a window is pending while they
 * differ. Scope "box" is this probe path, which every site shares; a site's
 * scope is md5 of its name, opened only by the redis module's failover on that
 * site (global-window-d8.php), so one site whose own connection fails never
 * clears the others. While a window is pending a request runs on the database
 * and refuses every database cache entry created before the window began
 * (global-valkey.inc); the first request that finds Valkey up clears what
 * Valkey kept from before the window and closes it. The files are handled like
 * the flag: read through lstat() as regular files of the id's own shape only,
 * written under a random name and renamed over. */
function _valkey_window_file($flag_path, $scope, $kind) {
  return dirname($flag_path).'/win.'.$scope.'.'.$kind;
}

function _valkey_window_read($path) {
  $st = @lstat($path);
  if (!is_array($st) || ($st['mode'] & 0170000) !== 0100000 || $st['size'] > 64) {
    return FALSE;
  }
  $id = trim((string) @file_get_contents($path, FALSE, NULL, 0, 64));
  if (!preg_match('/^[0-9]{9,11}\.[0-9]{6}-[0-9a-f]{32}$/', $id)) {
    return FALSE;
  }
  return $id;
}

function _valkey_window_write($path, $id) {
  $tmp = $path.'.'.md5(uniqid(mt_rand(), TRUE));
  $fh = @fopen($tmp, 'x');
  if ($fh === FALSE) {
    return FALSE;
  }
  $ok = (@fwrite($fh, $id."\n") !== FALSE);
  fclose($fh);
  if (!$ok || !@rename($tmp, $path)) {
    @unlink($tmp);
    return FALSE;
  }
  return TRUE;
}

function _valkey_window_start($id) {
  if ($id === FALSE) {
    return 0.0;
  }
  return (float) substr($id, 0, strpos($id, '-'));
}

/* The pending window's id, or FALSE when none is. */
function _valkey_window_pending($flag_path, $scope) {
  $open = _valkey_window_read(_valkey_window_file($flag_path, $scope, 'open'));
  if ($open === FALSE || $open === _valkey_window_read(_valkey_window_file($flag_path, $scope, 'closed'))) {
    return FALSE;
  }
  return $open;
}

/* Open a window of this scope unless one is pending; return the pending
 * window's start, or 0.0 when none could be recorded. Called with no flag path
 * by the failover cache factory, from the same request. */
function _valkey_window_mark($scope = 'box', $flag_path = NULL) {
  if (!preg_match('/^(box|[0-9a-f]{32})$/', (string) $scope)) {
    return 0.0;
  }
  if ($flag_path === NULL) {
    $flag_path = _valkey_backoff_flag_path('/var/tmp/fpm', '/data/conf/arch/valkey.disabled.flag');
  }
  $open = _valkey_window_pending($flag_path, $scope);
  if ($open !== FALSE) {
    return _valkey_window_start($open);
  }
  $id = sprintf('%.6F', microtime(TRUE)).'-'.md5(uniqid(mt_rand(), TRUE));
  if (!_valkey_window_write(_valkey_window_file($flag_path, $scope, 'open'), $id)) {
    return 0.0;
  }
  return _valkey_window_start($id);
}

/* The earliest start among the windows pending for this request's scopes:
 * every database cache entry this site wrote since then was written on the
 * database, so only older ones are refused. */
function _valkey_window_threshold($flag_path, $scopes) {
  $start = 0.0;
  foreach ($scopes as $scope) {
    $s = _valkey_window_start(_valkey_window_pending($flag_path, $scope));
    if ($s > 0 && ($start == 0 || $s < $start)) {
      $start = $s;
    }
  }
  return $start;
}

/* Clear what Valkey kept from before a pending window, then close it. One
 * request per window wins (SET NX in database 0, 30 s); every other request,
 * and the winner when the clear fails, runs on the database and leaves the
 * window pending for a later request. The box scope empties database 8, as a
 * restart does (Valkey keeps nothing on disk), and bumps the APCu serial; a
 * site's scope removes its own keys only (every copy of the name, as
 * provision's purges do). APCu needs no clear for correctness: a ChainedFast
 * bin whose write timestamp is gone stamps a new one and stops trusting every
 * older APCu entry. TRUE: Valkey may be used. */
function _valkey_window_recover($flag_path, $scope, $id, $socket_path, $host, $port, $pass, $connect_timeout_s, $read_timeout_s, $transport) {
  if (!class_exists('Redis')) {
    return FALSE;
  }
  $r = new Redis();
  $key = 'boa_window_recover_'.$scope.'_'.md5($id);
  $won = FALSE;
  try {
    if ($transport === 'socket') {
      $connected = $r->connect($socket_path);
    }
    else {
      $connected = $r->connect($host, $port, $connect_timeout_s);
    }
    if (!$connected) {
      return FALSE;
    }
    if (defined('Redis::OPT_READ_TIMEOUT')) {
      $r->setOption(Redis::OPT_READ_TIMEOUT, $read_timeout_s);
    }
    if ($pass !== '' && !$r->auth($pass)) {
      return FALSE;
    }
    if (!$r->set($key, '1', array('nx', 'ex' => 30))) {
      return FALSE;
    }
    $won = TRUE;
    if (!$r->select(8)) {
      throw new Exception('select');
    }
    if ($scope === 'box') {
      if (!$r->flushDb()) {
        throw new Exception('flushdb');
      }
    }
    else {
      $r->setOption(Redis::OPT_SCAN, Redis::SCAN_RETRY);
      $it = NULL;
      while (($keys = $r->scan($it, $scope.'_*', 1000)) !== FALSE) {
        if (!empty($keys)) {
          $r->del($keys);
        }
      }
    }
  }
  catch (Exception $e) {
    if ($won) {
      try {
        $r->select(0);
        $r->del($key);
      }
      catch (Exception $e2) {
      }
    }
    return FALSE;
  }
  _valkey_window_write(_valkey_window_file($flag_path, $scope, 'closed'), $id);
  if ($scope === 'box') {
    _valkey_window_write(_valkey_window_file($flag_path, 'apcu', 'serial'), $id);
  }
  try { $r->close(); } catch (Exception $e) {}
  return TRUE;
}

/* After a box window each FPM APCu segment (every pool of one PHP version
 * shares one) clears itself once (one clearer per segment, apcu_add), which
 * redis_flush_apcu_on_recovery switches; the CLI's cache is its own process's
 * and has nothing to clear. */
function _valkey_apcu_serial_sync($flag_path) {
  if (PHP_SAPI === 'cli' || !function_exists('apcu_fetch')) {
    return FALSE;
  }
  $serial = _valkey_window_read(_valkey_window_file($flag_path, 'apcu', 'serial'));
  if ($serial === FALSE || @apcu_fetch('boa_valkey_window_serial') === $serial) {
    return FALSE;
  }
  if (!@apcu_add('boa_valkey_window_clear_'.md5($serial), 1, 60)) {
    return FALSE;
  }
  @apcu_clear_cache();
  @apcu_store('boa_valkey_window_serial', $serial);
  return TRUE;
}

/* ------------------- Probe Valkey once with guard --------------------- */
$flag_path = _valkey_backoff_flag_path($flag_dir_run, $flag_file_fallback);
$flag_existed = (_valkey_backoff_mtime($flag_path) !== FALSE);
$skip_probe = _valkey_backoff_is_active($flag_path, $backoff_ttl_s);
$last_reason = 'init';
$valkey_transport = FALSE; // 'socket' or 'tcp' once a probe answered: the wiring must reuse the transport that worked
/* The scopes this request answers for: the box, and the site (md5 of its
 * name, as the redis module names its keys). $valkey_window_start > 0 means
 * this request runs on its database cache inside a pending window and must
 * refuse entries created before that time (global-valkey.inc). */
$valkey_window_scopes = array('box');
if (!empty($_SERVER['SERVER_NAME'])) {
  $valkey_window_scopes[] = md5(preg_replace('`^www\.`', '', $_SERVER['SERVER_NAME']));
}
$valkey_window_start = 0.0;

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
      $valkey_up = _valkey_probe_once($valkey_socket_path, $valkey_host, $valkey_port, $auth_pass, $connect_timeout_s, $read_timeout_s, $last_reason, $valkey_transport);
      if ($valkey_up) {
        break;
      }
      if ($last_reason === 'no-phpredis') {
        break; // retrying cannot help
      }
    }

    if ($valkey_up) {
      // Valkey answers again: the backoff is over. What it kept from before a
      // pending window is cleared before this request reads it; a request
      // that cannot do that now stays on the database.
      if ($flag_existed) {
        _valkey_backoff_clear($flag_path);
      }
      foreach ($valkey_window_scopes as $vw_scope) {
        $vw_id = _valkey_window_pending($flag_path, $vw_scope);
        if ($vw_id === FALSE) {
          continue;
        }
        // A site's window waits out the backoff TTL before its clear, as the
        // box's does: a site whose own connection keeps failing then reopens
        // one at most that often, and the requests meanwhile cache on the
        // database inside it.
        if ($vw_scope !== 'box' && microtime(TRUE) - _valkey_window_start($vw_id) < $backoff_ttl_s) {
          $valkey_up = FALSE;
          $last_reason = 'window-recovery';
          $valkey_window_start = _valkey_window_threshold($flag_path, $valkey_window_scopes);
          break;
        }
        if (_valkey_window_recover($flag_path, $vw_scope, $vw_id, $valkey_socket_path, $valkey_host, $valkey_port, $auth_pass, $connect_timeout_s, $read_timeout_s, $valkey_transport)) {
          _valkey_dbg_write($redis_debug_on, $redis_debug_log, 'VALKEY WINDOW action=clear scope='.$vw_scope.' id='.$vw_id);
        }
        else {
          $valkey_up = FALSE;
          $last_reason = 'window-recovery';
          $valkey_window_start = _valkey_window_threshold($flag_path, $valkey_window_scopes);
          _valkey_dbg_write($redis_debug_on, $redis_debug_log, 'VALKEY WINDOW action=wait scope='.$vw_scope.' id='.$vw_id);
          break;
        }
      }
      if ($valkey_up) {
        if ($flush_apcu_recov && _valkey_apcu_serial_sync($flag_path)) {
          _valkey_dbg_write($redis_debug_on, $redis_debug_log, 'VALKEY RECOVERY action=apcu_clear');
        }
        _valkey_dbg_write($redis_debug_on, $redis_debug_log, 'VALKEY UP action=clear flag='.$flag_path.' reason=ok');
      }
    } else {
      _valkey_backoff_touch($flag_path);
      _valkey_window_mark('box', $flag_path);
      $valkey_window_start = _valkey_window_threshold($flag_path, $valkey_window_scopes);
      _valkey_dbg_write($redis_debug_on, $redis_debug_log, 'VALKEY DOWN action=touch flag='.$flag_path.' reason='.(string) $last_reason);
    }
  } else {
    // Inside the backoff: a flag that no window was recorded for (written by
    // an earlier release) opens one now.
    $valkey_up = FALSE;
    $last_reason = 'backoff-active';
    _valkey_window_mark('box', $flag_path);
    $valkey_window_start = _valkey_window_threshold($flag_path, $valkey_window_scopes);
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
    } elseif ($last_reason === 'window-recovery') {
      $vk_state = 'window';
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
