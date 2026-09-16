<?php # global settings.php


/**
 * Optional site and platform level settings defined in the ini files
 * Note: the site-level ini file takes precedence over platform level ini
 *
 * Core-agnostic: nothing here calls a CMS API, so the parse is shared by
 * every chain head (global-<core>.inc for Drupal, global-bd.inc for
 * Backdrop) and exists exactly once in the tree. The only per-core
 * difference is where the files are looked up: the Drupal heads set nothing
 * and keep the historical anchors (cwd is the platform root when
 * settings.php runs, the site dir is sites/<SERVER_NAME>, normalised to
 * MAIN_SITE_NAME by global-main.inc); the Backdrop head sets $ini_base_dir
 * to BACKDROP_ROOT and $ini_site_dir to what conf_path() resolved, so the
 * site INI is found under bee and drush too, where SERVER_NAME is unset.
 * $ini_plr_src and $ini_loc_src stay platform-relative on every core: they
 * are what the X-Ini-*-Src dev headers report.
 *
 * Must remain PHP 5.6 compatible (legacy servers).
 */
if (!isset($all_ini) || !is_array($all_ini)) {
  $all_ini = (isset($boa_ini) && is_array($boa_ini)) ? $boa_ini : array();
}
if (!isset($ini_base_dir) || !is_string($ini_base_dir)) {
  $ini_base_dir = '';
}
if (empty($ini_site_dir)) {
  $ini_site_dir = 'sites/' . $_SERVER['SERVER_NAME'];
}
if (is_readable($ini_base_dir . 'sites/all/modules/boa_platform_control.ini')) {
  $ini_plr_src = 'sites/all/modules/boa_platform_control.ini';
}
if ($ini_plr_src) {
  $usr_plr_ini = array();
  $usr_plr_ini = parse_ini_file($ini_base_dir . $ini_plr_src);
}
if (is_readable($ini_base_dir . $ini_site_dir . '/modules/boa_site_control.ini')) {
  $ini_loc_src = $ini_site_dir . '/modules/boa_site_control.ini';
}
if ($ini_loc_src) {
  $usr_loc_ini = array();
  $usr_loc_ini = parse_ini_file($ini_base_dir . $ini_loc_src);
}
if (is_array($usr_plr_ini) && $usr_plr_ini) {
  $all_ini = array_merge($all_ini, $usr_plr_ini);
}
if (is_array($usr_loc_ini) && $usr_loc_ini) {
  $all_ini = array_merge($all_ini, $usr_loc_ini);
}
