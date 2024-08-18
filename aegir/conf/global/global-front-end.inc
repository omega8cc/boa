<?php # global settings.php


/**
 * More logic for the front-end only
 */
if (!$is_backend && isset($_SERVER['HTTP_HOST']) &&
    isset($_SERVER['SERVER_NAME'])) {
  if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) || isset($_SERVER['HTTPS'])) {
    $conf['https'] = TRUE;
    $request_type = ($_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' || $_SERVER['HTTPS'] === 'on') ? 'SSL' : 'NONSSL';
    if ($request_type === "SSL") { // we check for secure connection to set correct base_url
      $base_url = 'https://' . $_SERVER['HTTP_HOST'];
      if ($conf['install_profile'] != 'hostmaster') {
        $_SERVER['HTTPS'] = 'on';
        if ($drupal_core >= 7) {
          ini_set('session.cookie_secure', TRUE);
          if ($is_dev) {
            header('X-Cookie-Sec: YES');
          }
        }
      }
      if ($is_dev) {
        header('X-Local-Proto: https');
      }
    }
    else {
      if ($site_subdir && $raw_host) {
        $base_url = 'http://' . $raw_host . '/' . $site_subdir;
      }
      else {
        $base_url = 'http://' . $_SERVER['HTTP_HOST'];
      }
    }
  }
  else {
    if ($site_subdir && $raw_host) {
      $base_url = 'http://' . $raw_host . '/' . $site_subdir;
    }
    else {
      $base_url = 'http://' . $_SERVER['HTTP_HOST'];
    }
  }

  if ($base_url && $is_dev) {
    header("X-Base-Url: " . $base_url);
  }

  if ($site_subdir && $is_dev) {
    header("X-Site-Subdir: " . $site_subdir);
  }

  if ($all_ini['server_name_cookie_domain']) {
    $domain = '.' . preg_replace('`^www\.`', '', $_SERVER['SERVER_NAME']);
  }
  elseif ($site_subdir && isset($_SERVER['RAW_HOST'])) {
    $domain = '.' . preg_replace('`^www\.`', '', $_SERVER['RAW_HOST']);
  }
  else {
    $domain = '.' . preg_replace('`^www\.`', '', $_SERVER['HTTP_HOST']);
  }
  $domain = str_replace('..', '.', $domain);
  if (count(explode('.', $domain)) > 2 &&
      !is_numeric(str_replace('.', '', $domain))) {
    ini_set('session.cookie_domain', $domain);
    $cookie_domain = $domain;
    header("X-Cookie-Domain: " . $cookie_domain);
  }

  $this_prefix = preg_replace('`^www\.`', '', $_SERVER['SERVER_NAME']) . '_z_';
  if ($is_dev) {
    header("X-Redis-Prefix: " . $this_prefix);
  }

  if (isset($_SERVER['REQUEST_TIME']) &&
      isset($_SERVER['REMOTE_ADDR']) &&
      isset($_SERVER['HTTP_USER_AGENT']) &&
      !preg_match("/^\/esi\//", $_SERVER['REQUEST_URI'])) {

    // Determine if the site is running on HTTPS
    $request_type = 'NONSSL';
    if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) || isset($_SERVER['HTTPS'])) {
      $request_type = ($_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' || $_SERVER['HTTPS'] === 'on') ? 'SSL' : 'NONSSL';
    }
    if ($request_type === "SSL") {
      $is_https = TRUE;
      if ($is_dev) {
        header('X-Request-Type:' . $request_type);
      }
    }
    else {
      $is_https = FALSE;
      if ($is_dev) {
        header('X-Request-Type:' . $request_type);
      }
    }

    // Create a unique identifier for the request
    $identity = $_SERVER['REQUEST_TIME'] . $_SERVER['REMOTE_ADDR'] . $_SERVER['SERVER_NAME'] . $_SERVER['HTTP_USER_AGENT'];
    $identity = 'BD' . md5($identity);
    if ($is_dev) {
      header('X-Identity:' . $identity);
    }

    if ($drupal_core >= 8) {
      // Check if the user is logged in by looking for the session cookie.
      // The session cookie name starts with "SESS" or "SSESS" followed by a hash.
      // This check is not site specific in Drupal 8+ like it is in Drupal 7
      // or Drupal 6, but should be sufficient for the intended use case below.
      $cookie_prefix = ini_get('session.cookie_secure') ? 'SSESS' : 'SESS';
      $is_logged_in = FALSE;
      foreach ($_COOKIE as $key => $value) {
        if (strpos($key, $cookie_prefix) === 0) {
          $is_logged_in = TRUE;
          break;
        }
      }
      if ($is_dev) {
        header('X-Cookie-Prefix-A:' . $cookie_prefix);
        header('X-Is-Logged-In-A:' . $is_logged_in);
      }
    }
    elseif ($drupal_core === 7) {
      // For Drupal 7 use sha256 hash and cookie prefix based on session.cookie_secure
      $cookie_prefix = ini_get('session.cookie_secure') ? 'SSESS' : 'SESS';
      $test_sess_name = $cookie_prefix . substr(hash('sha256', $cookie_domain), 0, 32);
      if ($is_dev) {
        header('X-Cookie-Prefix-B:' . $cookie_prefix);
        header('X-Test-Sess-Name-B:' . $test_sess_name);
      }
    }
    else {
      // For Drupal 6 use md5 hash and SESS prefix only
      $cookie_prefix = 'SESS';
      $test_sess_name = $cookie_prefix . md5($cookie_domain);
      if ($is_dev) {
        header('X-Cookie-Prefix-C:' . $cookie_prefix);
        header('X-Test-Sess-Name-C:' . $test_sess_name);
      }
    }

    // Check if the session cookie is present
    if (isset($_COOKIE[$test_sess_name]) || $is_logged_in) {
      $is_anon = 'LOGGED';
    }
    else {
      $is_anon = 'ANONYMOUS';
    }
    if ($is_dev) {
      header('X-Is-Anon:' . $is_anon);
    }

    // Redirect not logged in visitors to homepage to protect admin URLs from bots
    if ($is_anon === 'ANONYMOUS') {
      if (preg_match("/\/(?:node\/[0-9]+\/edit|node\/add)/", $_SERVER['REQUEST_URI'])) {
        if (empty($all_ini['allow_anon_node_add'])) {
          header("HTTP/1.1 301 Moved Permanently");
          header("Location: " . $base_url . "/");
          header("Connection: close");
          exit;
        }
      }
      if (preg_match("/^\/(?:[a-z]{2}\/)?(?:admin|logout|privatemsg|approve)/", $_SERVER['REQUEST_URI'])) {
        if (empty($all_ini['disable_admin_dos_protection'])) {
          header("HTTP/1.1 301 Moved Permanently");
          header("Location: " . $base_url . "/");
          header("Connection: close");
          exit;
        }
      }
    }

    // Additional logic for caching or other needs
    if ($is_anon === 'ANONYMOUS' && !empty($all_ini['speed_booster_anon_cache_ttl']) && preg_match("/^[0-9]{2,}$/", $all_ini['speed_booster_anon_cache_ttl'])) {
      if ($all_ini['speed_booster_anon_cache_ttl'] > 10) {
        $expire_in_seconds = $all_ini['speed_booster_anon_cache_ttl'];
        header('X-Limit-Booster:' . $all_ini['speed_booster_anon_cache_ttl']);
      }
    }

    // Prevent turning the feature server site into a spam machine
    // Disable self-registration also on hostmaster
    if ($conf['install_profile'] === 'feature_server' ||
        $conf['install_profile'] === 'hostmaster') {
      $conf['user_register'] = 0; // Force "Only site administrators can create new user accounts"
    }
    if (!$is_bot && !$high_traffic) {
      if (preg_match("/^\/(?:[a-z]{2}\/)?(?:admin|cart|checkout|logout|privatemsg)/", $_SERVER['REQUEST_URI']) ||
          preg_match("/\/(?:node\/[0-9]+\/edit|node\/add|comment\/reply|approve|ajax_comments|commerce_currency_select)/", $_SERVER['REQUEST_URI']) ||
          preg_match("/(?:^dev\.|\.dev\.|\.devel\.)/", $_SERVER['HTTP_HOST'])) {
        $expire_in_seconds = '1';
        header('X-Limit-Booster: 1');
      }
      if (isset($_SERVER['REQUEST_URI']) &&
          preg_match("/(?:x-progress-id|ahah|progress\/|autocomplete|ajax|batch|js\/.*)/i", $_SERVER['REQUEST_URI'])) {
        $expire_in_seconds = '0';
        if ($is_dev) {
          header('X-Skip-Booster: AjaxRU');
        }
      }
      if (isset($_SERVER['QUERY_STRING']) &&
          preg_match("/(?:x-progress-id|ahah|progress\/|autocomplete|ajax|batch|js\/.*)/i", $_SERVER['QUERY_STRING'])) {
        $expire_in_seconds = '0';
        if ($is_dev) {
          header('X-Skip-Booster: AjaxQS');
        }
      }
      if (isset($_SERVER['REQUEST_METHOD']) &&
          $_SERVER['REQUEST_METHOD'] === 'POST') {
        if (!isset($_COOKIE['NoCacheID'])) {
          $lifetime = '15';
          setcookie('NoCacheID', 'POST' . $identity, $_SERVER['REQUEST_TIME'] + $lifetime, '/', $cookie_domain);
        }
        $expire_in_seconds = '0';
        if ($is_dev) {
          header('X-Skip-Booster: PostRM');
        }
      }
    }
    if ($is_bot) {
      if (!preg_match("/Pingdom/i", $_SERVER['HTTP_USER_AGENT']) &&
          !preg_match("/(?:rss|feed)/i", $_SERVER['REQUEST_URI'])) {
        $expire_in_seconds = '3600';
        if ($is_dev) {
          header('X-Bot-Booster: 3600');
        }
      }
    }
    if ($conf['install_profile'] != 'hostmaster' && ($expire_in_seconds > -1)) {
      header("X-Accel-Expires: " . $expire_in_seconds);
      if ($expire_in_seconds > -1 && $expire_in_seconds < 2) {
        $conf['cache'] = 0; // Disable page caching on the fly
      }
    }
  }
}


/**
 * Support files/styles with short URIs also for files not generated yet
 */
if (preg_match("/^\/files\/styles\//", $_SERVER['REQUEST_URI'])) {
  header("HTTP/1.1 301 Moved Permanently");
  header("Location: " . $base_url . "/sites/" . $_SERVER['SERVER_NAME'] . $_SERVER['REQUEST_URI']);
  header("Connection: close");
  exit;
}

