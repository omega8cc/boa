<?php
/**
 * BOA: the migration's 503 gate for Grav and Textpattern sites.
 *
 * The same rule as the HTTP-off block in global-mode.inc, which Drupal and
 * Backdrop sites run, for sites that never load the global settings chain:
 * the setup file Grav vhosts name (global-grav-gate.php) and the
 * private/config.php that provision writes for a Textpattern site include
 * this file first. Their vhosts leave the gate to it once verified with a
 * provision that knows it; an older vhost still tests both gate files in
 * nginx, by path, and so does a newer one while this file or Grav's
 * global-grav-gate.php is missing (nginx's open file cache keeps the answer
 * up to open_file_cache_valid: reload nginx after moving either by hand).
 *
 * static/control/http-off.pid holds every site of the account (its content
 * the TTL, 30 to 86400 seconds, else 300); static/control/http-off-host.pid
 * holds only the sites whose own name carries a name it lists, never the
 * account's control panel. Either file counts only as a regular file, never
 * a link, and only in a control folder that is the account's own: a real
 * directory that root or one of the account's identities owns, with no write
 * for others and group write only for group root or the account's own group.
 * The identities are the list root keeps for each account,
 * /data/conf/acct-uids/<account>; without a valid list the gate counts in any
 * folder. Keep this rule equal to global-mode.inc's.
 *
 * Deployed by barracuda; an edit here is overwritten.
 */
if (!function_exists('boa_http_off_gate')) {
  function boa_http_off_gate() {
    if (PHP_SAPI === 'cli' || PHP_SAPI === 'phpdbg'
      || !isset($_SERVER['DOCUMENT_ROOT'])
      || !preg_match('#^(/data/disk/([^/]+))/#', $_SERVER['DOCUMENT_ROOT'], $m)) {
      return;
    }
    $ttl = 0;
    $pid = $m[1] . '/static/control/http-off.pid';
    if (is_file($pid) && !is_link($pid)) {
      $ttl = (int) @file_get_contents($pid);
      if ($ttl < 30 || $ttl > 86400) {
        $ttl = 300;
      }
    }
    elseif (strpos($_SERVER['DOCUMENT_ROOT'], $m[1] . '/aegir/') !== 0) {
      $hpid = $m[1] . '/static/control/http-off-host.pid';
      if (is_file($hpid) && !is_link($hpid)) {
        // The site's own name, never the request's Host; failing both names,
        // hold, as global-mode.inc does.
        $site = '';
        if (isset($_SERVER['MAIN_SITE_NAME'])) {
          $site = strtolower($_SERVER['MAIN_SITE_NAME']);
        }
        elseif (isset($_SERVER['SERVER_NAME'])) {
          $site = strtolower($_SERVER['SERVER_NAME']);
        }
        if ($site === '') {
          $ttl = 300;
        }
        else {
          $names = @file($hpid, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
          if (is_array($names)) {
            foreach ($names as $name) {
              $name = strtolower(trim($name));
              if ($name !== '' && strpos($site, $name) !== FALSE) {
                $ttl = 300;
                break;
              }
            }
          }
        }
      }
    }
    if ($ttl > 0) {
      $ids = @file_get_contents('/data/conf/acct-uids/' . $m[2]);
      if (is_string($ids) && preg_match('/^[0-9]+(,[0-9]+)*$/', trim($ids))) {
        $own = FALSE;
        $st = @lstat($m[1] . '/static/control');
        if (is_array($st)
          && ($st['mode'] & 0170000) == 0040000
          && in_array((string) $st['uid'], explode(',', '0,' . trim($ids)), TRUE)
          && !($st['mode'] & 0002)) {
          if (!($st['mode'] & 0020) || $st['gid'] == 0) {
            $own = TRUE;
          }
          elseif (function_exists('posix_getgrgid')) {
            $gr = @posix_getgrgid($st['gid']);
            $own = is_array($gr) && isset($gr['name']) && $gr['name'] === $m[2];
          }
        }
        if (!$own) {
          $ttl = 0;
        }
      }
    }
    if ($ttl > 0) {
      header('HTTP/1.1 503 Service Unavailable');
      header('Status: 503 Service Unavailable');
      header('Retry-After: ' . $ttl);
      header('X-Accel-Expires: ' . $ttl);
      header('Cache-Control: no-store, must-revalidate');
      header('Content-Type: text/html; charset=utf-8');
      header('Connection: close');
      $tpl = '/var/www/nginx-default/maintenance.html';
      if (@is_readable($tpl)) {
        readfile($tpl);
      }
      else {
        echo '<!doctype html><title>Maintenance in progress</title>'
          . '<h1>Site maintenance in progress</h1>'
          . '<p>We will be back shortly.</p>';
      }
      exit;
    }
  }
}
boa_http_off_gate();
