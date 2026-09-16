<?php # global settings.php

/**
 * Backdrop chain head -- the Backdrop sibling of global-<core>.inc.
 *
 * Included by the Aegir Backdrop settings.php template (and by the
 * global.inc dispatcher for a Backdrop platform). It runs inside
 * backdrop_settings_initialize() scope, so $settings, $conf, $config,
 * $database and $cookie_domain are the variables settings.php itself writes.
 *
 * Same partials, same order as the Drupal chain heads, so every BOA INI
 * directive, mode gate and /data/conf override hook reaches a Backdrop site
 * exactly as it reaches a Drupal site. The one partial that writes Drupal
 * cache classes and D7 $conf (global-valkey.inc) is replaced by its Backdrop
 * sibling, global-bd-valkey.inc; the shared partials carry a $backdropcms arm
 * where the write target differs. $drupal_core stays FALSE on purpose: every
 * "$drupal_core >= N" test in the shared partials then evaluates FALSE on
 * every PHP version, whereas a string sentinel compares differently between
 * PHP 7 and PHP 8. Gate on $backdropcms instead.
 *
 * Must remain PHP 5.6 compatible (shared-tree file).
 */

/**
 * Include ini
 */
if (is_readable('/data/conf/global/global-ini.inc')) {
  include_once('/data/conf/global/global-ini.inc');
}

$backdropcms = TRUE;

/**
 * Backdrop anchors for the INI parse (global-ini-parse.inc): the platform
 * root is BACKDROP_ROOT and the site directory is what conf_path() resolved
 * for this request -- correct under bee and drush too, where SERVER_NAME is
 * unset. A '.' answer (no sites.php record for this host) leaves the Drupal
 * anchor, sites/<SERVER_NAME>, to global-main.inc.
 */
$ini_base_dir = defined('BACKDROP_ROOT') ? BACKDROP_ROOT . '/' : '';
$ini_site_dir = FALSE;
if (function_exists('conf_path')) {
  $ini_conf_path = conf_path();
  if (is_string($ini_conf_path) && $ini_conf_path !== '' && $ini_conf_path !== '.') {
    $ini_site_dir = preg_replace('#^\./#', '', $ini_conf_path);
  }
}

/**
 * The shared partials compare the D7 profile name; Backdrop keeps no such
 * $conf entry (its installed profile lives in state), so name it empty
 * rather than let every request read an undefined key.
 */
if (!isset($conf) || !is_array($conf)) {
  $conf = array();
}
if (!isset($conf['install_profile'])) {
  $conf['install_profile'] = '';
}

/**
 * Include mode
 */
if (is_readable('/data/conf/global/global-mode.inc')) {
  include_once('/data/conf/global/global-mode.inc');
}

/**
 * Install detection. The Drupal chain reads it off the Drush command
 * (provision-install); a Backdrop install runs inside core's own installer
 * process, which defines MAINTENANCE_MODE 'install' before it bootstraps.
 * Keeps the cache wiring off while the site is being built, as on Drupal.
 */
if (defined('MAINTENANCE_MODE') && MAINTENANCE_MODE === 'install') {
  $is_install = TRUE;
}

/**
 * Include main
 */
if (is_readable('/data/conf/global/global-main.inc')) {
  include_once('/data/conf/global/global-main.inc');
}

/**
 * Include redirects
 */
if (is_readable('/data/conf/global/global-settings.inc')) {
  include_once('/data/conf/global/global-settings.inc');
}

/**
 * Optional system level early overrides
 */
if (is_readable('/data/conf/settings.global.inc')) {
  require_once "/data/conf/settings.global.inc";
}

/**
 * Include front-end
 */
if (is_readable('/data/conf/global/global-front-end.inc')) {
  include_once('/data/conf/global/global-front-end.inc');
}

/**
 * If include valkey/redis
 */
if (is_readable('/data/conf/global/global-if-valkey.inc')) {
  include_once('/data/conf/global/global-if-valkey.inc');
}
elseif (is_readable('/data/conf/global/global-if-redis.inc')) {
  include_once('/data/conf/global/global-if-redis.inc');
}

/**
 * Optional system level overrides
 */
if (is_readable('/data/conf/override.global.inc')) {
  require_once "/data/conf/override.global.inc";
}

/**
 * Include valkey/redis -- the Backdrop wiring
 */
if (is_readable('/data/conf/global/global-bd-valkey.inc')) {
  include_once('/data/conf/global/global-bd-valkey.inc');
}

/**
 * Include newrelic
 */
if (is_readable('/data/conf/global/global-newrelic.inc')) {
  include_once('/data/conf/global/global-newrelic.inc');
}

/**
 * Include extra
 */
if (is_readable('/data/conf/global/global-extra.inc')) {
  include_once('/data/conf/global/global-extra.inc');
}
