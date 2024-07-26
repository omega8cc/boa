<?php # global settings.php

/**
 * New Relic - see: https://newrelic.com/docs/php/per-directory-settings#perdir-rollup
 * Support for background job borrowed from https://drupal.org/project/newrelic_drush_plugin
 */
if (extension_loaded('newrelic') && $all_ini['enable_newrelic_integration']) {
  $this_instance = FALSE;
  if ($is_backend) {
    $context = drush_get_context();
    $uri = FALSE;
    if (isset($context['DRUSH_URI'])) {
      $uri = $context['DRUSH_URI'];
      $uri = str_replace('http://', '', $uri);
      $uri = str_replace('https://', '', $uri);
    }
    elseif (isset($context['DRUSH_DRUPAL_SITE'])) {
      $uri = $context['DRUSH_DRUPAL_SITE'];
    }
    if ($uri) {
      $this_instance = 'Drush Site: ' . $uri;
      if (isset($command['command']) && isset($command['arguments'])) {
        $drush_command = array_merge(array($command['command']), $command['arguments']);
        newrelic_add_custom_parameter('Drush command', implode(' ', $drush_command));
        newrelic_name_transaction(implode(' ', $drush_command));
        newrelic_background_job(TRUE);
      }
    }
  }
  else {
    if (isset($_SERVER['SERVER_NAME'])) {
      $this_instance = 'Web Site: ' . $_SERVER['SERVER_NAME'];
      //newrelic_background_job(FALSE);
    }
  }
  if ($this_instance) {
    ini_set('newrelic.appname', $this_instance);
    newrelic_set_appname($this_instance);
  }
}
elseif (extension_loaded('newrelic') && !$all_ini['enable_newrelic_integration']) {
  newrelic_disable_autorum();
  newrelic_ignore_apdex();
  newrelic_ignore_transaction();
}
