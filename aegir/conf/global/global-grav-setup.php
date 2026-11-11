<?php
/**
 * BOA: the setup file every Grav site's web requests load.
 *
 * Each Grav vhost names it in GRAV_SETUP_PATH while it is here. Grav creates
 * its cache, log and media folders with mkdir(0777) under the process umask,
 * and the PHP-FPM masters run with 0022, so a folder the web server made was
 * 2755 and the account's own users could not empty it: their cache clear and
 * package update listed its files as "Unable to delete file" until a Verify
 * or the nightly handed it back. Under 0002 a request creates folders and
 * files with the group write the hosting model gives them, as the shell's
 * grav command does. PHP puts the worker's umask back when the request ends.
 *
 * Then Grav's own lookup, unchanged: the site's setup.php, else
 * user/setup.php, in Grav's scope, its array returned as Grav would read it.
 * Deployed by barracuda; an edit here is overwritten.
 */
umask(0002);
$boa_grav_setup = GRAV_WEBROOT . '/setup.php';
if (!is_file($boa_grav_setup)) {
  $boa_grav_setup = GRAV_WEBROOT . '/' . GRAV_USER_PATH . '/setup.php';
}
return is_file($boa_grav_setup) ? (array) include $boa_grav_setup : array();
