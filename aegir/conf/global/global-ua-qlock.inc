<?php # global settings.php

/**
 * Login/admin IP lock — query-string route form.
 *
 * The per-site login/admin IP lock (static/control/ip/user_admin.txt, rendered
 * by user_admin_access.sh) is an nginx layer that matches the clean $uri. Drupal
 * 6/7 and Backdrop also route on $_GET['q'], and every route in the vhost passes
 * the query string to the backend, so a request such as /?q=user/login arrives
 * with $uri '/' and reaches the login form past that layer. This gate closes it
 * where q is read the way Drupal reads it. Drupal 8+ does not route on q and
 * never includes this file; clean-path /user and /admin from a locked visitor
 * were already refused by nginx and never reach here.
 *
 * The lock verdict is passed by nginx: $_SERVER['BOA_UA_LK_SELF'] is the site's
 * own value, judged on the real visitor on a direct hit and behind the wildcard
 * SSL front and the panel proxy alike (the vhost reads the address those on-box
 * hops forward). A front or proxy that also forwards its own verdict in
 * X-BOA-UA-LK can only tighten it: that header is read only from an on-box hop
 * (a loopback peer, or the box talking to itself, REMOTE_ADDR == SERVER_ADDR),
 * and a "1" there locks while a "0" never unlocks. A remote client's own header
 * is never read; those tiers overwrite it, so it cannot be smuggled through.
 *
 * PHP 5.6 safe: this runs under the legacy backend too (Drupal 6 on PHP 5.6).
 */
if (empty($is_backend) && isset($_SERVER['BOA_UA_LK_SELF'])) {
  $boa_ua_lk = $_SERVER['BOA_UA_LK_SELF'];
  if (isset($_SERVER['HTTP_X_BOA_UA_LK']) && isset($_SERVER['REMOTE_ADDR'])) {
    $boa_ua_self = isset($_SERVER['SERVER_ADDR']) ? $_SERVER['SERVER_ADDR'] : '';
    if (($_SERVER['REMOTE_ADDR'] === '127.0.0.1'
      || $_SERVER['REMOTE_ADDR'] === '::1'
      || ($boa_ua_self !== '' && $_SERVER['REMOTE_ADDR'] === $boa_ua_self))
      && $_SERVER['HTTP_X_BOA_UA_LK'] === '1') {
      $boa_ua_lk = '1';
    }
    unset($boa_ua_self);
  }
  if ($boa_ua_lk === '1') {
    $boa_ua_hit = FALSE;
    // The query-string route form Drupal 6/7 and Backdrop still route on. A
    // non-scalar q (?q[]=...) cannot reach a real page and is refused too, so it
    // is never an escape hatch; a scalar q is matched the way the nginx layer
    // matches the clean path (case-insensitive, leading slashes trimmed).
    if (isset($_GET['q'])) {
      if (!is_scalar($_GET['q'])) {
        $boa_ua_hit = TRUE;
      }
      elseif (preg_match('#^(?:user|admin)(?:/|$)#i', ltrim((string) $_GET['q'], '/'))) {
        $boa_ua_hit = TRUE;
      }
    }
    // The clean path, resolved the way Drupal resolves the first segment: a
    // trailing run of non-alphanumerics (/user+, /user%20, /user.) reaches the
    // same menu item, which the nginx clean-URI match does not catch. Only an
    // exact user or admin first segment matches, so /userxyz and /user-guide
    // stay public.
    if (!$boa_ua_hit && isset($_SERVER['REQUEST_URI'])) {
      $boa_ua_p = (string) $_SERVER['REQUEST_URI'];
      $boa_ua_qpos = strpos($boa_ua_p, '?');
      if ($boa_ua_qpos !== FALSE) {
        $boa_ua_p = substr($boa_ua_p, 0, $boa_ua_qpos);
      }
      $boa_ua_p = ltrim(urldecode($boa_ua_p), '/');
      $boa_ua_slash = strpos($boa_ua_p, '/');
      if ($boa_ua_slash !== FALSE) {
        $boa_ua_p = substr($boa_ua_p, 0, $boa_ua_slash);
      }
      $boa_ua_p = preg_replace('/[^a-zA-Z0-9]+$/', '', $boa_ua_p);
      if (strcasecmp($boa_ua_p, 'user') === 0 || strcasecmp($boa_ua_p, 'admin') === 0) {
        $boa_ua_hit = TRUE;
      }
      unset($boa_ua_p, $boa_ua_qpos, $boa_ua_slash);
    }
    if ($boa_ua_hit) {
      header('HTTP/1.1 403 Forbidden');
      header('Content-Type: text/plain; charset=utf-8');
      print "403 Forbidden\n";
      exit;
    }
    unset($boa_ua_hit);
  }
  unset($boa_ua_lk);
}
