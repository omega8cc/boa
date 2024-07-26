<?php # global settings.php


/**
 * Include ini
 */
if (is_readable('/data/conf/global/global-ini.inc')) {
  include_once('/data/conf/global/global-ini.inc');
}

$drupal_core = '8';

/**
 * Include mode
 */
if (is_readable('/data/conf/global/global-mode.inc')) {
  include_once('/data/conf/global/global-mode.inc');
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
 * If include redis
 */
if (is_readable('/data/conf/global/global-if-redis.inc')) {
  include_once('/data/conf/global/global-if-redis.inc');
}

/**
 * Optional system level overrides
 */
if (is_readable('/data/conf/override.global.inc')) {
  require_once "/data/conf/override.global.inc";
}

/**
 * Include redis
 */
if (is_readable('/data/conf/global/global-redis.inc')) {
  include_once('/data/conf/global/global-redis.inc');
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

