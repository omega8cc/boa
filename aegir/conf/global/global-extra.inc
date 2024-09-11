<?php # global settings.php


/**
 * Use site specific composer_manager dir
 */
if ($all_ini['set_composer_manager_vendor_dir'] && !$is_install) {
  if ($drupal_core >= 8) {
    $config['composer_manager.settings']['vendor_dir'] = 'sites/' . $_SERVER['SERVER_NAME'] . '/vendor';
  }
  else {
    $conf['composer_manager_vendor_dir'] = 'sites/' . $_SERVER['SERVER_NAME'] . '/vendor';
  }
}

/**
 * Domain Access Module Paths Detection
 */
if ($all_ini['auto_detect_domain_access_integration']) {
  if (is_readable('sites/all/modules/domain/settings.inc')) {
    $da_inc = 'sites/all/modules/domain/settings.inc';
  }
  elseif (is_readable('sites/all/modules/contrib/domain/settings.inc')) {
    $da_inc = 'sites/all/modules/contrib/domain/settings.inc';
  }
  elseif (is_readable('profiles/' . $conf['install_profile'] . '/modules/domain/settings.inc')) {
    $da_inc = 'profiles/' . $conf['install_profile'] . '/modules/domain/settings.inc';
  }
  elseif (is_readable('profiles/' . $conf['install_profile'] . '/modules/contrib/domain/settings.inc')) {
    $da_inc = 'profiles/' . $conf['install_profile'] . '/modules/contrib/domain/settings.inc';
  }
}

/**
 * Domain Access Module inc should not be loaded during installation
 */
if ($is_install) {
  $da_inc    = FALSE;
}

/**
 * Domain Access Module inc loading
 */
if (!$custom_da) {
  if ($da_inc) {
    require_once($da_inc);
  }
}

/**
 * Drupal for Facebook (fb)
 *
 * Important:
 * Facebook client libraries will not work properly if arg_separator.output is not &
 * The default value is &amp;. Change this in settings.php. Make the value "&"
 * https://drupal.org/node/205476
 */
if (!$custom_fb && $all_ini['auto_detect_facebook_integration']) {
  if (is_readable('sites/all/modules/fb/fb_settings.inc')) {
    ini_set('arg_separator.output', '&');
    require_once "sites/all/modules/fb/fb_settings.inc";
    $conf['fb_api_file'] = "sites/all/modules/fb/facebook-platform/php/facebook.php";
  }
  elseif (is_readable('sites/all/modules/contrib/fb/fb_settings.inc')) {
    ini_set('arg_separator.output', '&');
    require_once "sites/all/modules/contrib/fb/fb_settings.inc";
    $conf['fb_api_file'] = "sites/all/modules/contrib/fb/facebook-platform/php/facebook.php";
  }
  elseif (is_readable('profiles/' . $conf['install_profile'] . '/modules/fb/fb_settings.inc')) {
    ini_set('arg_separator.output', '&');
    require_once 'profiles/' . $conf['install_profile'] . '/modules/fb/fb_settings.inc';
    $conf['fb_api_file'] = 'profiles/' . $conf['install_profile'] . '/modules/fb/facebook-platform/php/facebook.php';
  }
  elseif (is_readable('profiles/' . $conf['install_profile'] . '/modules/contrib/fb/fb_settings.inc')) {
    ini_set('arg_separator.output', '&');
    require_once 'profiles/' . $conf['install_profile'] . '/modules/contrib/fb/fb_settings.inc';
    $conf['fb_api_file'] = 'profiles/' . $conf['install_profile'] . '/modules/contrib/fb/facebook-platform/php/facebook.php';
  }
}

/**
 * Unset config arrays on non-dev URLs
 */
if (!$is_dev) {
  unset($boa_ini);
  unset($usr_plr_ini);
  unset($usr_loc_ini);
  unset($all_ini);
}
