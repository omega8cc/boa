<?php # global settings.php


/**
 * Bots detection
 */
if (isset($_SERVER['HTTP_USER_AGENT']) &&
    preg_match("/(?:crawl|bot|spider|tracker|click|parser|google|yahoo|yandex|baidu|bing)/i", $_SERVER['HTTP_USER_AGENT'])) {
  $is_bot = TRUE;
}


/**
 * Site mode detection - works also for aliases
 */
if (isset($_SERVER['HTTP_HOST']) &&
    (preg_match("/(?:^dev\.|\.dev\.)/i", $_SERVER['HTTP_HOST']) ||
     preg_match("/(?:^devel\.|\.devel\.)/i", $_SERVER['HTTP_HOST']) ||
     preg_match("/(?:^tmp\.|\.tmp\.)/i", $_SERVER['HTTP_HOST']) ||
     preg_match("/(?:^temp\.|\.temp\.)/i", $_SERVER['HTTP_HOST']) ||
     preg_match("/(?:^temporary\.|\.temporary\.)/i", $_SERVER['HTTP_HOST']) ||
     preg_match("/(?:^test\.|\.test\.)/i", $_SERVER['HTTP_HOST']) ||
     preg_match("/(?:^testing\.|\.testing\.)/i", $_SERVER['HTTP_HOST']))) {
  $is_tmp = TRUE;
}


/**
 * Dev mode detection - works only for aliases
 */
if (isset($_SERVER['HTTP_HOST']) &&
    isset($_SERVER['MAIN_SITE_NAME']) &&
    preg_match("/(?:^dev\.|^devel\.|\.dev\.|\.devel\.)/i", $_SERVER['HTTP_HOST']) &&
    $_SERVER['HTTP_HOST'] != $_SERVER['MAIN_SITE_NAME'] &&
    $_SERVER['HTTP_HOST'] != $_SERVER['SERVER_NAME'] &&
    !$is_backend) {
  $is_dev = TRUE;
}


/**
 * Backend and task detection
 */
if (function_exists('drush_get_command')) {
  $command = drush_get_command();
  if (isset($command['command'])) {
    $command = explode(" ", $command['command']);
    if (isset($command[0])) {
      if (!preg_match("/^help/", $command[0])) {
        $is_backend = TRUE;
      }
      if (preg_match("/^(provision-install|provision-save|provision-backup|php-eval)/", $command[0])) {
        if (!is_readable('/data/conf/clstr.cnf')) {
          $is_install = TRUE;
        }
      }
    }
  }
}
else {
  if (php_sapi_name() === 'cli' || PHP_SAPI === 'cli') {
    $is_backend = TRUE;
  }
}


/**
 * Detecting subdirectory mode
 */
if (isset($_SERVER['SITE_SUBDIR'])) {
  $site_subdir = $_SERVER['SITE_SUBDIR'];
}
if (isset($_SERVER['RAW_HOST'])) {
  $raw_host = $_SERVER['RAW_HOST'];
}


/**
 * The nodns mode detection
 */
if (isset($_SERVER['HTTP_HOST']) &&
    (preg_match("/(?:^nodns\.|\.nodns\.)/i", $_SERVER['HTTP_HOST']))) {
  $no_dns = TRUE;
}


/**
 * Local nodns request detection
 */
if (isset($_SERVER['REMOTE_ADDR']) &&
    (preg_match("/(^127\.0\.0\.1)$/i", $_SERVER['REMOTE_ADDR']) ||
     preg_match("/(^127\.0\.0\.1\, 127\.0\.0\.1)$/i", $_SERVER['REMOTE_ADDR']))) {
  $local_req = TRUE;
  // A loopback peer that carries X-Real-IP is a proxy on this box, the
  // wildcard SSL front among them, and the front overwrites that header
  // with its own visitor. Judge that visitor the way the front does: local
  // only when it is loopback or the address it connected to (X-Forwarded-By
  // is that address and port), which is how the box reaches its own sites.
  if (!empty($_SERVER['HTTP_X_REAL_IP'])) {
    $boa_hop_visitor = trim($_SERVER['HTTP_X_REAL_IP']);
    $boa_hop_server = '';
    if (!empty($_SERVER['HTTP_X_FORWARDED_BY'])) {
      $boa_hop_server = trim($_SERVER['HTTP_X_FORWARDED_BY']);
      $boa_hop_colon = strrpos($boa_hop_server, ':');
      if ($boa_hop_colon !== FALSE) {
        $boa_hop_server = substr($boa_hop_server, 0, $boa_hop_colon);
      }
    }
    if ($boa_hop_visitor !== '127.0.0.1' && $boa_hop_visitor !== '::1' &&
        $boa_hop_visitor !== $boa_hop_server) {
      $local_req = FALSE;
    }
    unset($boa_hop_visitor, $boa_hop_server, $boa_hop_colon);
  }
}


/**
 * Local path request check
 */
if (preg_match("/\/api\/hidden\//", $_SERVER['REQUEST_URI'])) {
  $hidden_uri = TRUE;
}


/**
 * Drupal core or other apps id
 */
if ($drupal_core == 6) {
  $drupal_id = 'DVI';
}
elseif ($drupal_core == 7) {
  $drupal_id = 'DVII';
}
elseif ($drupal_core == 8) {
  $drupal_id = 'DVIII';
}
elseif ($drupal_core == 9) {
  $drupal_id = 'DIX';
}
elseif ($drupal_core == 10) {
  $drupal_id = 'DX';
}
elseif ($drupal_core == 11) {
  $drupal_id = 'DXI';
}
elseif (!empty($backdropcms)) {
  $drupal_id = 'BD';
}
else {
  $drupal_id = 'ND';
}
if ($drupal_id && $is_dev && !$is_backend) {
  header('X-Backend: ' . $drupal_id);
}


/**
 * Billing suspend short-circuit
 *
 * Presence of /data/conf/suspended/<oct>.pid blocks all sites on the
 * Octopus account with a 503. Managed by `boa suspend <user>` and
 * `boa unsuspend <user>`. The flag lives outside the account tree on
 * purpose: the account owner must not be able to remove it via shell
 * or SFTP access. Unlike the http-off gate below, the 503 must never
 * stick in caches once the account is unsuspended, hence no-store for
 * downstream and a short microcache TTL; boa also purges the speed
 * cache on both toggle points.
 */
if (!$is_backend && !$is_install && isset($_SERVER['DOCUMENT_ROOT'])) {
  if (preg_match('#^/data/disk/([^/]+)/#', $_SERVER['DOCUMENT_ROOT'], $_suspended_m)) {
    if (file_exists('/data/conf/suspended/' . $_suspended_m[1] . '.pid')) {
      header('HTTP/1.1 503 Service Unavailable');
      header('Status: 503 Service Unavailable');
      header('Retry-After: 3600');
      header('X-Accel-Expires: 60');
      header('Cache-Control: no-store, must-revalidate');
      header('Content-Type: text/html; charset=utf-8');
      header('Connection: close');
      echo '<!doctype html><title>Site temporarily unavailable</title>'
        . '<h1>Site temporarily unavailable</h1>'
        . '<p>Please check back later or contact the site owner.</p>';
      exit;
    }
  }
}


/**
 * HTTP-off migration short-circuit
 *
 * Presence of /data/disk/<oct>/static/control/http-off.pid blocks all
 * sites on the Octopus account with a 503. xoct touches this during
 * export and removes it once the proxy vhost is in place. Replaces
 * readonlymode use which is unreliable on busy commerce sites and
 * unavailable via system drush 8 on Drupal 8+.
 *
 * File contents (integer seconds) override the default TTL of 300s
 * for both Nginx microcache (X-Accel-Expires) and downstream caches.
 *
 * The per-host twin, static/control/http-off-host.pid, holds only the
 * sites NAMED under a listed hostname (one per line). A whole-server move
 * lifts the account gate as soon as the old box relays to the new one,
 * while the sites named under the OLD box hostname are still being renamed
 * there and have no server block to be relayed to: they stay on 503
 * through this file until the rename is done. The test is the site's own
 * name (MAIN_SITE_NAME where the location carries it, the server name
 * otherwise), never the request's Host, and the rule is the one the hostname rename and the deferral use
 * -- the name carries the hostname -- so a held site is held under every
 * alias it serves, and a client-domain site is never held through an
 * alias that happens to sit under the box hostname. The account's own
 * control panel is named under the box hostname too and is exempt: it is
 * never relayed and must stay reachable for its admins. Default TTL,
 * never read from the file. A symlink is ignored: root writes the list.
 */
if (!$is_backend && !$is_install && isset($_SERVER['DOCUMENT_ROOT'])) {
  if (preg_match('#^(/data/disk/[^/]+)/#', $_SERVER['DOCUMENT_ROOT'], $_http_off_m)) {
    $_http_off_ttl = 0;
    $_http_off_pid = $_http_off_m[1] . '/static/control/http-off.pid';
    if (file_exists($_http_off_pid)) {
      $_http_off_ttl = (int) @file_get_contents($_http_off_pid);
      if ($_http_off_ttl < 30 || $_http_off_ttl > 86400) {
        $_http_off_ttl = 300;
      }
    }
    elseif (strpos($_SERVER['DOCUMENT_ROOT'], $_http_off_m[1] . '/aegir/') !== 0) {
      $_http_off_hpid = $_http_off_m[1] . '/static/control/http-off-host.pid';
      if (is_file($_http_off_hpid) && !is_link($_http_off_hpid)) {
        // The site's own name. MAIN_SITE_NAME is the Ægir one, but a location
        // that declares its own fastcgi_param set drops every server-level
        // param (the cron entry points do exactly that, and the shared vhost
        // include says so in its own header), so fall back to the server name
        // and, failing both, HOLD: while this file exists, a request that
        // still reaches PHP here belongs to a site that was not relayed, and
        // those are the sites this gate is holding.
        $_http_off_site = '';
        if (isset($_SERVER['MAIN_SITE_NAME'])) {
          $_http_off_site = strtolower($_SERVER['MAIN_SITE_NAME']);
        }
        elseif (isset($_SERVER['SERVER_NAME'])) {
          $_http_off_site = strtolower($_SERVER['SERVER_NAME']);
        }
        if ($_http_off_site === '') {
          $_http_off_ttl = 300;
        }
        else {
          $_http_off_names = @file($_http_off_hpid, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
          if (is_array($_http_off_names)) {
            foreach ($_http_off_names as $_http_off_name) {
              $_http_off_name = strtolower(trim($_http_off_name));
              if ($_http_off_name !== ''
                && strpos($_http_off_site, $_http_off_name) !== FALSE) {
                $_http_off_ttl = 300;
                break;
              }
            }
          }
        }
      }
    }
    if ($_http_off_ttl > 0) {
      header('HTTP/1.1 503 Service Unavailable');
      header('Status: 503 Service Unavailable');
      header('Retry-After: ' . $_http_off_ttl);
      header('X-Accel-Expires: ' . $_http_off_ttl);
      // no-store downstream: the gate must not outlive the window in a
      // browser or CDN (the microcache above is purged at every toggle)
      header('Cache-Control: no-store, must-revalidate');
      header('Content-Type: text/html; charset=utf-8');
      header('Connection: close');
      $_http_off_tpl = '/var/www/nginx-default/maintenance.html';
      if (@is_readable($_http_off_tpl)) {
        readfile($_http_off_tpl);
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
