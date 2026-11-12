<?php
/**
 * BOA: the setup file a Grav vhost names once it leaves the migration's 503
 * gate to PHP.
 *
 * First the gate (global-http-off.php), by the rule Drupal and Backdrop
 * sites follow: Grav reaches this file before any plugin, session or page
 * runs. Then BOA's Grav setup file (global-grav-setup.php) as Grav reads it,
 * or, without it, the lookup Grav makes itself: the site's setup.php, else
 * user/setup.php. A file of its own, so a barracuda pass of a tree that does
 * not know the gate leaves it as it is, and a Grav vhost that names it keeps
 * the gate. While this file or the gate file is missing, such a vhost tests
 * the gate files in nginx by path.
 * Deployed by barracuda; an edit here is overwritten.
 */
if (is_file('/data/conf/global/global-http-off.php')) {
  include '/data/conf/global/global-http-off.php';
}
if (is_file('/data/conf/global/global-grav-setup.php')) {
  return include '/data/conf/global/global-grav-setup.php';
}
$boa_grav_setup = GRAV_WEBROOT . '/setup.php';
if (!is_file($boa_grav_setup)) {
  $boa_grav_setup = GRAV_WEBROOT . '/' . GRAV_USER_PATH . '/setup.php';
}
return is_file($boa_grav_setup) ? (array) include $boa_grav_setup : array();
