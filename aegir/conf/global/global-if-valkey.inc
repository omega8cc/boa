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

/* A noredis=1 request of a site that otherwise uses Valkey runs on its
 * database: inside an outage window (a pending one, or the backoff) it refuses
 * entries older than the window and is recorded like any other request there
 * (see Outage windows below); outside one what it changes never reaches
 * Valkey. */
$valkey_noredis = FALSE;
if (!$is_bot && isset($_SERVER['REQUEST_URI'])) {
  if (preg_match("/noredis=1/", $_SERVER['REQUEST_URI'])) {
    $valkey_noredis = !empty($use_valkey);
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
 * beside the backoff flag: win.<scope>.open holds the id of the window last
 * opened ("<start microtime>-<md5>"), win.<scope>.closed the id of the last
 * one recovered; a window is pending while they differ. Scope "box" is this
 * probe path, which every site shares; a site's scope is md5 of its name,
 * opened by the redis module's failover on that site (global-window-d8.php)
 * or by a request whose PHP has no phpredis, so one site's own trouble never
 * touches the others.
 *
 * While a window is pending a request runs on the database, refuses every
 * database cache entry created before the window began (global-valkey.inc)
 * and records its site for the window: win.<scope>.ran.<md5 of the pattern>
 * holds "<window id> <pattern>", the pattern being the site's key prefix in
 * Valkey (md5 of the name, then _, on Drupal; md5 of the database host, name
 * and table prefix, then :, on Backdrop) or * for the whole of database 8.
 * The first request that finds Valkey up recovers the window: it removes the
 * recorded sites' keys and closes it, and sites with no request on the
 * database in the window keep theirs. A request still running on the database
 * when a recovery of its window began records its site again when it ends, in
 * the box window pending then (opened for it when none is), so what it wrote
 * after the clear is cleared too.
 *
 * The files are handled like the flag: read through lstat() as regular files
 * of their own shape only, written under a random name and renamed over, and
 * never removed (a record of an older window is simply not read). */
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
  // Every pool and the CLI read it, whatever umask made it.
  @chmod($tmp, 0644);
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

function _valkey_window_scope_ok($scope) {
  return (bool) preg_match('/^(box|[0-9a-f]{32})$/', (string) $scope);
}

function _valkey_window_flag_path() {
  return _valkey_backoff_flag_path('/var/tmp/fpm', '/data/conf/arch/valkey.disabled.flag');
}

/* Open a window of this scope unless one is pending; the pending window's id,
 * or FALSE when none could be recorded. A window opened here carries its
 * selective token (win.<scope>.selective, its id): its recovery may rely on
 * the records. Requests opening one at once each rename their own id over the
 * file; reading it back makes them use the one that stayed. */
function _valkey_window_open($scope, $flag_path = NULL) {
  if (!_valkey_window_scope_ok($scope)) {
    return FALSE;
  }
  if ($flag_path === NULL) {
    $flag_path = _valkey_window_flag_path();
  }
  $open = _valkey_window_pending($flag_path, $scope);
  if ($open !== FALSE) {
    return $open;
  }
  $id = sprintf('%.6F', microtime(TRUE)).'-'.md5(uniqid(mt_rand(), TRUE));
  if (!_valkey_window_write(_valkey_window_file($flag_path, $scope, 'open'), $id)) {
    return FALSE;
  }
  _valkey_window_write(_valkey_window_file($flag_path, $scope, 'selective'), $id);
  $now = _valkey_window_pending($flag_path, $scope);
  return ($now !== FALSE) ? $now : $id;
}

/* The start of the window it opened or found pending, or 0.0, for a caller
 * that needs only that (global-window-d8.php of an earlier release). */
function _valkey_window_mark($scope = 'box', $flag_path = NULL) {
  return _valkey_window_start(_valkey_window_open($scope, $flag_path));
}

/* The earliest start among the windows pending for this request's scopes and
 * the one it already holds: every database cache entry this site wrote since
 * then was written on the database, so only older ones are refused. Holding
 * the start keeps a window a concurrent recovery just closed from leaving the
 * request on the database with no threshold at all. */
function _valkey_window_threshold($flag_path, $scopes, $held = 0.0) {
  $start = (float) $held;
  foreach ($scopes as $scope) {
    $s = _valkey_window_start(_valkey_window_pending($flag_path, $scope));
    if ($s > 0 && ($start == 0 || $s < $start)) {
      $start = $s;
    }
  }
  return $start;
}

/* ---- Records of the sites that ran on the database in a window. */
function _valkey_window_pattern_ok($pattern) {
  return (bool) preg_match('/^([0-9a-f]{32}[_:]|\*)$/', (string) $pattern);
}

function _valkey_window_ran_file($flag_path, $scope, $pattern) {
  return _valkey_window_file($flag_path, $scope, 'ran.'.md5($pattern));
}

/* A record: array(window id, pattern), or FALSE. */
function _valkey_window_read_ran($path) {
  $st = @lstat($path);
  if (!is_array($st) || ($st['mode'] & 0170000) !== 0100000 || $st['size'] > 128) {
    return FALSE;
  }
  $line = trim((string) @file_get_contents($path, FALSE, NULL, 0, 128));
  if (!preg_match('/^([0-9]{9,11}\.[0-9]{6}-[0-9a-f]{32}) ([0-9a-f]{32}[_:]|\*)$/', $line, $m)) {
    return FALSE;
  }
  return array($m[1], $m[2]);
}

/* Record a site for a window, once: nothing is written while the record
 * already names the window. A site that cannot be recorded would keep its
 * keys, so the window loses its selective token and its recovery clears as an
 * earlier release did. */
function _valkey_window_record($flag_path, $scope, $id, $pattern) {
  if ($id === FALSE || !_valkey_window_scope_ok($scope) || !_valkey_window_pattern_ok($pattern)) {
    return FALSE;
  }
  $path = _valkey_window_ran_file($flag_path, $scope, $pattern);
  $rec = _valkey_window_read_ran($path);
  if ($rec !== FALSE && $rec[0] === $id) {
    return TRUE;
  }
  if (_valkey_window_write($path, $id.' '.$pattern)) {
    return TRUE;
  }
  @unlink(_valkey_window_file($flag_path, $scope, 'selective'));
  return FALSE;
}

/* The patterns recorded for one window of a scope. */
function _valkey_window_ran_list($flag_path, $scope, $id) {
  $found = array();
  $files = @glob(dirname($flag_path).'/win.'.$scope.'.ran.*');
  if (is_array($files)) {
    foreach ($files as $f) {
      $rec = _valkey_window_read_ran($f);
      if ($rec !== FALSE && $rec[0] === $id) {
        $found[$rec[1]] = TRUE;
      }
    }
  }
  return array_keys($found);
}

/* The marker of the request recovering a window: 'deciding' from the moment
 * it won the lease, 'selective' or 'full' once it has decided how to clear
 * (rewritten as it works, at least every 5 s), 'failed' when it gave up:
 * array(window id, state, mtime), or FALSE. */
function _valkey_window_read_recovering($path) {
  $st = @lstat($path);
  if (!is_array($st) || ($st['mode'] & 0170000) !== 0100000 || $st['size'] > 128) {
    return FALSE;
  }
  $line = trim((string) @file_get_contents($path, FALSE, NULL, 0, 128));
  if (!preg_match('/^([0-9]{9,11}\.[0-9]{6}-[0-9a-f]{32}) (deciding|selective|full|failed)$/', $line, $m)) {
    return FALSE;
  }
  return array($m[1], $m[2], $st['mtime']);
}

/* This request runs on the database in these windows (scope => id): its site
 * is recorded in each, and checked again when the request ends. */
function _valkey_window_join($flag_path, $runs) {
  if (empty($runs) || !is_array($runs)) {
    return;
  }
  $pattern = isset($GLOBALS['valkey_window_pattern']) ? (string) $GLOBALS['valkey_window_pattern'] : '*';
  foreach ($runs as $scope => $id) {
    if ($id === FALSE || !_valkey_window_scope_ok($scope)) {
      continue;
    }
    _valkey_window_record($flag_path, $scope, $id, $pattern);
    $GLOBALS['valkey_window_runs'][$scope] = $id;
  }
  $GLOBALS['valkey_window_flag'] = $flag_path;
  if (empty($GLOBALS['valkey_window_guard'])) {
    register_shutdown_function('_valkey_window_end');
    $GLOBALS['valkey_window_guard'] = new BoaValkeyWindowGuard();
  }
}

/* The redis module's failover on this site (global-window-d8.php): open or
 * join the site's window, stamp its seen file (the window waits while the
 * site's requests keep failing) and record the site; the window's start. */
function _valkey_window_failover($scope) {
  if ($scope === 'box' || !_valkey_window_scope_ok($scope)) {
    return 0.0;
  }
  $flag_path = _valkey_window_flag_path();
  $id = _valkey_window_open($scope, $flag_path);
  if ($id === FALSE) {
    return 0.0;
  }
  _valkey_backoff_touch(_valkey_window_file($flag_path, $scope, 'seen'));
  _valkey_window_join($flag_path, array($scope => $id));
  return _valkey_window_start($id);
}

/* When the request ends: a window it ran in that a recovery began on, or that
 * is no longer the one pending, may have been cleared before what the request
 * wrote, so its site is recorded again in a window of the same scope pending
 * now (opened for it when none is), which the next request that finds Valkey
 * up recovers: the box window for a late run of the box window, the site's
 * own for a late run of a site window only, so one site's trouble stays its
 * own. It runs from a shutdown function, which a fatal error still reaches,
 * and again from the guard's destructor, which comes after Drupal's own
 * shutdown work and after Drush's exit(); a second run only joins what the
 * first made. */
function _valkey_window_end() {
  if (empty($GLOBALS['valkey_window_runs']) || empty($GLOBALS['valkey_window_flag'])) {
    return;
  }
  $flag_path = $GLOBALS['valkey_window_flag'];
  $pattern = isset($GLOBALS['valkey_window_pattern']) ? (string) $GLOBALS['valkey_window_pattern'] : '*';
  // Backdrop's module takes its prefix from the database settings as they
  // stand after every settings file (core keeps them in the global
  // $databases); a prefix a later file changed is recorded too.
  $moved = FALSE;
  if (!empty($GLOBALS['valkey_window_backdrop']) && $pattern !== '*'
      && isset($GLOBALS['databases']['default']['default']['host'], $GLOBALS['databases']['default']['default']['database'])) {
    $db = $GLOBALS['databases']['default']['default'];
    $dbp = isset($db['prefix']) ? $db['prefix'] : '';
    if (is_array($dbp)) {
      $dbp = isset($dbp['default']) ? $dbp['default'] : '';
    }
    $now = md5($db['host'].$db['database'].(string) $dbp).':';
    if ($now !== $pattern) {
      // The early one stays recorded as well: the site's next requests name
      // it when they check whether a pass clears them.
      $GLOBALS['valkey_window_early'] = $pattern;
      $GLOBALS['valkey_window_pattern'] = $pattern = $now;
      $moved = TRUE;
    }
  }
  // A window still pending and not being recovered (a failed attempt clears
  // nothing, and the next one reads the records afresh) is cleared after this
  // request's writes; while the site's own window is such a one, it covers the
  // site (a site kept on its database by its own window never reopens the
  // box's).
  $target = FALSE;
  $own = FALSE;
  foreach ($GLOBALS['valkey_window_runs'] as $scope => $id) {
    $rec = _valkey_window_read_recovering(_valkey_window_file($flag_path, $scope, 'recovering'));
    if (_valkey_window_pending($flag_path, $scope) === $id && !($rec !== FALSE && $rec[0] === $id && $rec[1] !== 'failed')) {
      if ($moved) {
        _valkey_window_record($flag_path, $scope, $id, $pattern);
      }
      if ($scope !== 'box') {
        $own = TRUE;
      }
      continue;
    }
    if ($scope === 'box' || $target === FALSE) {
      $target = $scope;
    }
  }
  if ($target === FALSE || $own) {
    return;
  }
  for ($i = 0; $i < 3; $i++) {
    $id = _valkey_window_open($target, $flag_path);
    if ($id === FALSE) {
      return;
    }
    _valkey_window_record($flag_path, $target, $id, $pattern);
    if (!empty($GLOBALS['valkey_window_early']) && $GLOBALS['valkey_window_early'] !== $pattern) {
      _valkey_window_record($flag_path, $target, $id, $GLOBALS['valkey_window_early']);
    }
    if (_valkey_window_pending($flag_path, $target) === $id) {
      $GLOBALS['valkey_window_runs'] = array($target => $id);
      return;
    }
  }
}

if (!class_exists('BoaValkeyWindowGuard', FALSE)) {
  /* Held in $GLOBALS by a request that ran on the database in a window. */
  class BoaValkeyWindowGuard {
    public function __destruct() {
      _valkey_window_end();
    }
  }
}

/* Keys a recovery leaves in place, read after the first colon (the end of the
 * site's prefix): lock and flood keys (held locks, login counters) and the
 * invalidation state, which only grows (Drupal 8+ cache tag counters and a
 * bin's last delete-all, a Drupal 6, 7 or Backdrop bin's last flush): with
 * those removed mid-pass an entry written meanwhile would count as valid. */
function _valkey_window_keep_key($key) {
  $c = strpos($key, ':');
  if ($c === FALSE) {
    return FALSE;
  }
  return (bool) preg_match('/^(lock|flood|cachetags):|^[^:]*:(_last_flush|_redis_last_delete_all)$/', substr($key, $c + 1));
}

/* Extend the lease while it is still this request's; on database 0, back to 8. */
function _valkey_window_lease_refresh($r, $key, $token) {
  if (!$r->select(0)) {
    return FALSE;
  }
  $ok = ($r->get($key) === $token && $r->expire($key, 15));
  return ($r->select(8) && $ok);
}

/* Whether this site's keys are part of the pass of this window: a site window
 * always removes its own name's prefix; otherwise the site's record must name
 * the window. */
function _valkey_window_listed($flag_path, $scope, $id, $pattern) {
  if ($pattern === '*' || ($scope !== 'box' && $pattern === $scope.'_')) {
    return TRUE;
  }
  $own = _valkey_window_read_ran(_valkey_window_ran_file($flag_path, $scope, $pattern));
  return ($own !== FALSE && $own[0] === $id);
}

/* Another request recovers this window. A site the window did not record goes
 * past it ('pass') as soon as the winner has written that it makes a selective
 * pass (its keys are not part of it); any other request waits for the window
 * to stop being the pending one (recovered; the caller reads the scope again),
 * then uses Valkey: running on the database meanwhile would record its site
 * again for every recovery. It waits while the winner's marker stays fresh (a
 * live winner rewrites it at least every 5 s), until the caller's deadline,
 * and stops when the winner gave up and no other took over within a second,
 * or no marker names the window within 1 s (the winner died or cannot write
 * here). TRUE: no longer pending; 'pass': use Valkey past it; FALSE: run on
 * the database this time. */
function _valkey_window_await($flag_path, $scope, $id, $pattern, $deadline) {
  $t0 = microtime(TRUE);
  while (TRUE) {
    if (_valkey_window_pending($flag_path, $scope) !== $id) {
      return TRUE;
    }
    $rec = _valkey_window_read_recovering(_valkey_window_file($flag_path, $scope, 'recovering'));
    $said = ($rec !== FALSE && $rec[0] === $id);
    if ($said && $rec[1] === 'selective' && !_valkey_window_listed($flag_path, $scope, $id, $pattern)) {
      return 'pass';
    }
    if (($said && $rec[1] === 'failed' && time() - $rec[2] >= 1)
        || (!$said && microtime(TRUE) - $t0 >= 1.0)
        || ($said && time() - $rec[2] > 7) || microtime(TRUE) >= $deadline) {
      return FALSE;
    }
    usleep(50000);
  }
}

/* Recover a pending window, then close it. One request per window wins the
 * lease (SET NX of its own token in database 0, 15 s, extended every 5 s while
 * it works; the window closes only while the lease is still its own); the
 * others get 'busy'. The winner first checks that the window is still pending
 * (another winner may have closed it just before), then writes its marker
 * (win.<scope>.recovering): 'deciding', then how it clears, rewritten at every
 * extension, 'failed' when it gives up. It removes the recorded sites' keys
 * from database 8 in one SCAN pass, keeping lock, flood and invalidation keys
 * (_valkey_window_keep_key()); a site window also removes its own name's
 * prefix and never more. A box window empties the whole of database 8 instead,
 * as a restart does (Valkey keeps nothing on disk), and bumps the APCu serial,
 * when it cannot rely on its records: the window has no selective token (an
 * earlier release opened it, or a record could not be written), it has no
 * record (whoever opens one runs on the database and records itself), a
 * record names the whole database, it began within two minutes of this file
 * being written (requests of the release before may have run on the database
 * unrecorded), a selective pass of this window failed before, or the database
 * holds over 500,000 keys. A record of the whole database in a site window
 * goes to a box window. Records written for the window after they were read
 * go into a new window of the same scope. APCu needs no clear after a pass: a
 * ChainedFast bin whose write timestamp is gone stamps a new one and stops
 * trusting every older APCu entry. TRUE: done (the caller reads the scopes
 * again: a new window may be pending); 'busy': another request recovers it;
 * FALSE: not now. */
function _valkey_window_recover($flag_path, $scope, $id, $socket_path, $host, $port, $pass, $connect_timeout_s, $read_timeout_s, $transport) {
  if (!class_exists('Redis')) {
    return FALSE;
  }
  $r = new Redis();
  $key = 'boa_window_recover_'.$scope.'_'.md5($id);
  $token = md5(uniqid(mt_rand(), TRUE));
  $marker = _valkey_window_file($flag_path, $scope, 'recovering');
  $won = FALSE;
  $full = FALSE;
  $mode = 'deciding';
  $listed = array();
  $patterns = array();
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
      // A pass takes longer than a probe's answer.
      $r->setOption(Redis::OPT_READ_TIMEOUT, max((float) $read_timeout_s, 5.0));
    }
    if ($pass !== '' && !$r->auth($pass)) {
      return FALSE;
    }
    if (!$r->set($key, $token, array('nx', 'ex' => 15))) {
      return 'busy';
    }
    $won = TRUE;
    if (_valkey_window_pending($flag_path, $scope) !== $id) {
      // Closed by a winner whose lease ended just before this one began.
      $r->del($key);
      return TRUE;
    }
    if (!_valkey_window_write($marker, $id.' deciding')) {
      throw new Exception('recovering');
    }
    $listed = _valkey_window_ran_list($flag_path, $scope, $id);
    $patterns = $listed;
    if ($scope === 'box') {
      $vw_st = @stat(__FILE__);
      $full = (_valkey_window_read(_valkey_window_file($flag_path, $scope, 'selective')) !== $id
        || empty($patterns) || in_array('*', $patterns, TRUE)
        || !is_array($vw_st) || _valkey_window_start($id) < $vw_st['ctime'] + 120
        || _valkey_window_read(_valkey_window_file($flag_path, $scope, 'failed')) === $id);
    }
    else {
      // The site's own name's prefix too, unless the records name Backdrop's
      // database prefix (its module never uses the name's), so one prefix
      // usually remains and the pass can let Valkey match it.
      $patterns = array_values(array_unique(array_diff($patterns, array('*'))));
      $vw_bd = FALSE;
      foreach ($patterns as $p) {
        if (substr($p, -1) === ':') {
          $vw_bd = TRUE;
        }
      }
      if (!$vw_bd && !in_array($scope.'_', $patterns, TRUE)) {
        $patterns[] = $scope.'_';
      }
    }
    if (!$r->select(8)) {
      throw new Exception('select');
    }
    if (!$full && $scope === 'box' && $r->dbSize() > 500000) {
      $full = TRUE;
    }
    $mode = $full ? 'full' : 'selective';
    if (!_valkey_window_write($marker, $id.' '.$mode)) {
      throw new Exception('recovering');
    }
    if ($full) {
      if (!$r->flushDb()) {
        throw new Exception('flushdb');
      }
    }
    elseif (!empty($patterns)) {
      $set = array();
      foreach ($patterns as $p) {
        $set[$p] = TRUE;
      }
      // Every reply comes back, empty ones too, so the lease and the marker
      // are kept fresh on a long sparse pass.
      $r->setOption(Redis::OPT_SCAN, Redis::SCAN_NORETRY);
      $match = (count($set) === 1) ? $patterns[0].'*' : NULL;
      $it = NULL;
      $lease_at = microtime(TRUE);
      while (($keys = $r->scan($it, $match, 1000)) !== FALSE) {
        $drop = array();
        foreach ($keys as $k) {
          if (isset($set[substr($k, 0, 33)]) && !_valkey_window_keep_key($k)) {
            $drop[] = $k;
          }
        }
        if (!empty($drop)) {
          $r->del($drop);
        }
        if (microtime(TRUE) - $lease_at > 5) {
          if (!_valkey_window_lease_refresh($r, $key, $token) || !_valkey_window_write($marker, $id.' '.$mode)) {
            throw new Exception('lease');
          }
          $lease_at = microtime(TRUE);
        }
      }
    }
    if (!$r->select(0) || $r->get($key) !== $token) {
      throw new Exception('lease');
    }
  }
  catch (Exception $e) {
    if ($won) {
      // While the lease is still its own (or Valkey cannot say): tell the
      // requests waiting on it to stop, and leave a box pass cut short to a
      // full clear next time. A winner that lost its lease leaves the marker
      // to the one that took over.
      $mine = TRUE;
      try {
        $r->select(0);
        $mine = ($r->get($key) === $token);
        if ($mine) {
          $r->del($key);
        }
      }
      catch (Exception $e2) {
      }
      if ($mine) {
        _valkey_window_write($marker, $id.' failed');
        if ($mode === 'selective' && $scope === 'box') {
          _valkey_window_write(_valkey_window_file($flag_path, $scope, 'failed'), $id);
        }
      }
    }
    return FALSE;
  }
  // Follow-ups before the close, so the scope never shows nothing pending
  // while sites still need a pass: a site window's whole-database record goes
  // to a box window; records written for this window after they were read go
  // to a new window of this scope, which replaces it as the pending one.
  if (!$full) {
    $late = array_diff(_valkey_window_ran_list($flag_path, $scope, $id), $listed);
    if ($scope !== 'box' && in_array('*', $listed, TRUE)) {
      $late[] = '*';
    }
    $same = array();
    foreach (array_unique($late) as $p) {
      if ($p === '*' && $scope !== 'box') {
        _valkey_window_record($flag_path, 'box', _valkey_window_open('box', $flag_path), '*');
      }
      else {
        $same[] = $p;
      }
    }
    if (!empty($same)) {
      $next = sprintf('%.6F', microtime(TRUE)).'-'.md5(uniqid(mt_rand(), TRUE));
      $ok = TRUE;
      foreach ($same as $p) {
        $ok = _valkey_window_write(_valkey_window_ran_file($flag_path, $scope, $p), $next.' '.$p) && $ok;
      }
      if ($ok) {
        _valkey_window_write(_valkey_window_file($flag_path, $scope, 'selective'), $next);
      }
      _valkey_window_write(_valkey_window_file($flag_path, $scope, 'open'), $next);
    }
  }
  _valkey_window_write(_valkey_window_file($flag_path, $scope, 'closed'), $id);
  if ($full && $scope === 'box') {
    _valkey_window_write(_valkey_window_file($flag_path, 'apcu', 'serial'), $id);
  }
  try {
    $r->del($key);
    $r->close();
  }
  catch (Exception $e) {
  }
  return TRUE;
}

/* After a box window cleared in full each FPM APCu segment (every pool of one
 * PHP version shares one) clears itself once (one clearer per segment,
 * apcu_add), which redis_flush_apcu_on_recovery switches; the CLI's cache is
 * its own process's and has nothing to clear. */
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
 * name, the start of every Drupal 6, 7 and 8+ key of the site).
 * $valkey_window_start > 0 means this request runs on its database cache
 * inside a pending window and must refuse entries created before that time
 * (global-valkey.inc). $vw_runs lists the windows it runs in (scope => id);
 * what the window code reads later (the cache factory, the end of the
 * request) is in $GLOBALS, as settings are read inside a function. */
$valkey_window_scopes = array('box');
if (!empty($_SERVER['SERVER_NAME'])) {
  $valkey_window_scopes[] = md5(preg_replace('`^www\.`', '', $_SERVER['SERVER_NAME']));
}
$valkey_window_start = 0.0;
$vw_runs = array();
/* The site's key prefix in Valkey, which a record of it names. Backdrop's
 * module names keys by md5 of the database host, name and table prefix
 * (Redis_Client::getGlobalPrefix()), read the way Backdrop core reads the
 * settings (backdrop_settings_initialize()): $database as a URL string (with
 * $database_prefix) or as an array (with its own prefix) wins over the
 * $databases array. Unknown: * (the whole of database 8). */
$vw_pattern = isset($valkey_window_scopes[1]) ? $valkey_window_scopes[1].'_' : '*';
if (!empty($backdropcms)) {
  $vw_pattern = '*';
  $vw_db = NULL;
  if (!empty($database) && is_string($database) && $database !== 'mysql://user:pass@localhost/database_name') {
    $vw_url = @parse_url($database);
    if (is_array($vw_url) && isset($vw_url['host'], $vw_url['path'])) {
      $vw_db = array('host' => $vw_url['host'], 'database' => rawurldecode(substr($vw_url['path'], 1)), 'prefix' => !empty($database_prefix) ? $database_prefix : '');
    }
  }
  elseif (!empty($database) && is_array($database) && isset($database['host'], $database['database'])
      && $database != array('database' => 'database_name', 'username' => 'user', 'password' => 'pass', 'host' => 'localhost')) {
    $vw_db = $database;
  }
  elseif (isset($databases['default']['default']['host'], $databases['default']['default']['database'])) {
    $vw_db = $databases['default']['default'];
  }
  if ($vw_db !== NULL) {
    $vw_dbp = isset($vw_db['prefix']) ? $vw_db['prefix'] : '';
    if (is_array($vw_dbp)) {
      $vw_dbp = isset($vw_dbp['default']) ? $vw_dbp['default'] : '';
    }
    $vw_pattern = md5($vw_db['host'].$vw_db['database'].(string) $vw_dbp).':';
  }
}
$GLOBALS['valkey_window_pattern'] = $vw_pattern;
$GLOBALS['valkey_window_backdrop'] = !empty($backdropcms);

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
      // Every pending window of this request's scopes is recovered, or waited
      // for, before Valkey is used. A recovery can leave a window pending (one
      // reopened meanwhile, late records, a site's whole-database record moved
      // to the box), so the scopes are read again, three rounds at most; what
      // is still pending then keeps the request on the database.
      // One waiting budget for the whole check; $vw_pass holds the windows a
      // selective pass is clearing without this site, which it goes past.
      $vw_handled = FALSE;
      $vw_deadline = microtime(TRUE) + 30.0;
      $vw_pass = array();
      for ($vw_round = 0; $valkey_up && $vw_round < 3; $vw_round++) {
        $vw_handled = FALSE;
        foreach ($valkey_window_scopes as $vw_scope) {
          $vw_id = _valkey_window_pending($flag_path, $vw_scope);
          if ($vw_id === FALSE || (isset($vw_pass[$vw_scope]) && $vw_pass[$vw_scope] === $vw_id)) {
            continue;
          }
          $vw_handled = TRUE;
          // A site's window waits while requests of the site keep failing to
          // use Valkey (win.<site>.seen, stamped by the module's failover and
          // by a PHP without phpredis): those can only run on the database, so
          // the site's other requests stay there with them rather than on a
          // cache those never update, and a site whose own connection keeps
          // failing reopens one at most once per backoff TTL.
          $vw_seen = ($vw_scope !== 'box') ? _valkey_backoff_mtime(_valkey_window_file($flag_path, $vw_scope, 'seen')) : FALSE;
          if ($vw_seen !== FALSE && time() - $vw_seen < $backoff_ttl_s) {
            $valkey_up = FALSE;
            $last_reason = 'window-recovery';
            $vw_runs[$vw_scope] = $vw_id;
            break 2;
          }
          $vw_rc = _valkey_window_recover($flag_path, $vw_scope, $vw_id, $valkey_socket_path, $valkey_host, $valkey_port, $auth_pass, $connect_timeout_s, $read_timeout_s, $valkey_transport);
          if ($vw_rc === 'busy') {
            // A Backdrop request counts as named by every pass: the prefix it
            // read may not be the one a later settings file leaves.
            $vw_aw = _valkey_window_await($flag_path, $vw_scope, $vw_id, empty($backdropcms) ? $vw_pattern : '*', $vw_deadline);
            if ($vw_aw === 'pass') {
              $vw_pass[$vw_scope] = $vw_id;
            }
            if ($vw_aw !== FALSE) {
              _valkey_dbg_write($redis_debug_on, $redis_debug_log, 'VALKEY WINDOW action=awaited scope='.$vw_scope.' id='.$vw_id);
              continue;
            }
          }
          elseif ($vw_rc === TRUE) {
            _valkey_dbg_write($redis_debug_on, $redis_debug_log, 'VALKEY WINDOW action=clear scope='.$vw_scope.' id='.$vw_id);
            continue;
          }
          $valkey_up = FALSE;
          $last_reason = 'window-recovery';
          $vw_runs[$vw_scope] = $vw_id;
          _valkey_dbg_write($redis_debug_on, $redis_debug_log, 'VALKEY WINDOW action=wait scope='.$vw_scope.' id='.$vw_id);
          break 2;
        }
        if (!$vw_handled) {
          break;
        }
      }
      if ($valkey_up && $vw_handled) {
        foreach ($valkey_window_scopes as $vw_scope) {
          $vw_id = _valkey_window_pending($flag_path, $vw_scope);
          if ($vw_id !== FALSE && !(isset($vw_pass[$vw_scope]) && $vw_pass[$vw_scope] === $vw_id)) {
            $valkey_up = FALSE;
            $last_reason = 'window-recovery';
            $vw_runs[$vw_scope] = $vw_id;
          }
        }
      }
      if ($valkey_up) {
        if ($flush_apcu_recov && _valkey_apcu_serial_sync($flag_path)) {
          _valkey_dbg_write($redis_debug_on, $redis_debug_log, 'VALKEY RECOVERY action=apcu_clear');
        }
        _valkey_dbg_write($redis_debug_on, $redis_debug_log, 'VALKEY UP action=clear flag='.$flag_path.' reason=ok');
      }
    } elseif ($last_reason === 'no-phpredis') {
      // This PHP has no phpredis: a condition of this request, not of Valkey,
      // so the box's backoff and its window stay untouched (one such site set
      // them on every request and kept every site of the box on its database,
      // then cleared Valkey for all of them). The site runs on its database in
      // a window of its own, kept pending while such requests keep coming.
      if (isset($valkey_window_scopes[1])) {
        $vw_runs[$valkey_window_scopes[1]] = _valkey_window_open($valkey_window_scopes[1], $flag_path);
        _valkey_backoff_touch(_valkey_window_file($flag_path, $valkey_window_scopes[1], 'seen'));
      }
      _valkey_dbg_write($redis_debug_on, $redis_debug_log, 'VALKEY NOPHPREDIS action=site-window flag='.$flag_path);
    } else {
      _valkey_backoff_touch($flag_path);
      $vw_runs['box'] = _valkey_window_open('box', $flag_path);
      _valkey_dbg_write($redis_debug_on, $redis_debug_log, 'VALKEY DOWN action=touch flag='.$flag_path.' reason='.(string) $last_reason);
    }
  } else {
    // Inside the backoff: a flag that no window was recorded for (written by
    // an earlier release) opens one now.
    $valkey_up = FALSE;
    $last_reason = 'backoff-active';
    $vw_runs['box'] = _valkey_window_open('box', $flag_path);
    _valkey_dbg_write($redis_debug_on, $redis_debug_log, 'VALKEY SKIP reason=backoff-active flag='.$flag_path);
  }
}
elseif ($valkey_noredis) {
  // Inside the backoff the box is in an outage window, opened by whichever
  // request comes first, this one included.
  if ($skip_probe) {
    $vw_runs['box'] = _valkey_window_open('box', $flag_path);
  }
  foreach ($valkey_window_scopes as $vw_scope) {
    $vw_id = _valkey_window_pending($flag_path, $vw_scope);
    if ($vw_id !== FALSE) {
      $vw_runs[$vw_scope] = $vw_id;
    }
  }
}

/* On the database inside windows: every window pending for its scopes counts,
 * the earliest start among them (or the one it held, which a concurrent
 * recovery may have just closed) is the threshold, and the site is recorded. */
$vw_runs = array_filter($vw_runs, 'is_string');
if (!empty($vw_runs)) {
  foreach ($valkey_window_scopes as $vw_scope) {
    $vw_id = _valkey_window_pending($flag_path, $vw_scope);
    if ($vw_id !== FALSE && !isset($vw_runs[$vw_scope])) {
      $vw_runs[$vw_scope] = $vw_id;
    }
  }
  $vw_held = 0.0;
  foreach ($vw_runs as $vw_id) {
    $vw_s = _valkey_window_start($vw_id);
    if ($vw_s > 0 && ($vw_held == 0 || $vw_s < $vw_held)) {
      $vw_held = $vw_s;
    }
  }
  $valkey_window_start = _valkey_window_threshold($flag_path, $valkey_window_scopes, $vw_held);
  _valkey_window_join($flag_path, $vw_runs);
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
