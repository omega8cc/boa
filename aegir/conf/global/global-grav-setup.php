<?php
/**
 * BOA: the setup file a Grav site's web requests load.
 *
 * A Grav vhost rendered since this file shipped (the site's first Verify
 * after the server's upgrade) names it in GRAV_SETUP_PATH while nginx finds
 * it. Grav creates most of its cache, log and media folders with mkdir(0777)
 * under the process umask, and the PHP-FPM masters run with 0022, so a folder
 * the web server made was 2755 and the account's own users could not empty
 * it: their cache clear and package update listed its files as "Unable to
 * delete file" until a Verify or the nightly handed it back. Under 0002 a
 * request creates folders and files with the group write the hosting model
 * gives them, as the shell's grav command does; what Grav creates with its
 * own narrower mode keeps it (the debugger's Clockwork folder 0700, the
 * private security key 0600). PHP puts the worker's umask back when the
 * request ends.
 *
 * Then the lookup Grav makes when no GRAV_SETUP_PATH is set: the site's
 * setup.php, else user/setup.php, in Grav's scope, its array returned as Grav
 * would read it. The vhost's param takes the name, so a GRAV_SETUP_PATH in a
 * site's own .env layers (which only the account's backend user can write)
 * does not reach its web requests. nginx's open file cache can keep a removed
 * file's answer for up to open_file_cache_valid, and Grav stops on a
 * GRAV_SETUP_PATH that names no file: reload nginx after removing it by hand.
 * Deployed by barracuda; an edit here is overwritten.
 */
umask(0002);
$boa_grav_setup = GRAV_WEBROOT . '/setup.php';
if (!is_file($boa_grav_setup)) {
  $boa_grav_setup = GRAV_WEBROOT . '/' . GRAV_USER_PATH . '/setup.php';
}
return is_file($boa_grav_setup) ? (array) include $boa_grav_setup : array();
