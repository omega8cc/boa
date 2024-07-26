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
}


/**
 * Local path request check
 */
if (preg_match("/\/api\/hidden\//", $_SERVER['REQUEST_URI'])) {
  $hidden_uri = TRUE;
}



