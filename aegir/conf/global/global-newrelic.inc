<?php # global settings.php

/**
 * New Relic Integration for Drupal with Drush Compatibility (8, 12, 13)
 *
 * Supports background jobs and sets appropriate New Relic parameters.
 */
if (extension_loaded('newrelic') && !empty($all_ini['enable_newrelic_integration'])) {
  $this_instance = FALSE;

  if ($is_backend) {
    $uri = FALSE;

    // Check if drush_get_context exists (Drush 8)
    if (function_exists('drush_get_context')) {
      // Drush 8 context retrieval
      $context = drush_get_context();
      if (isset($context['DRUSH_URI'])) {
        $uri = $context['DRUSH_URI'];
      }
      elseif (isset($context['DRUSH_DRUPAL_SITE'])) {
        $uri = $context['DRUSH_DRUPAL_SITE'];
      }
    }
    else {
      // Drush 9+ context retrieval
      // Attempt to retrieve URI from environment variables or Drush services
      // Drush commands can pass the URI as an environment variable or argument

      // Example: Using environment variable (you might need to set this in Drush commands)
      if (isset($_SERVER['DRUSH_URI'])) {
        $uri = $_SERVER['DRUSH_URI'];
      }
      elseif (isset($_SERVER['DRUPAL_SITE_URI'])) {
        $uri = $_SERVER['DRUPAL_SITE_URI'];
      }
      else {
        // Fallback: Attempt to determine URI using Drupal APIs
        // Note: In Drush context, some Drupal services might not be fully bootstrapped
        try {
          $request = \Drupal::request();
          $uri = $request->getSchemeAndHttpHost();
        }
        catch (\Exception $e) {
          // Unable to determine URI; proceed without setting it
        }
      }
    }

    if ($uri) {
      // Clean the URI by removing the scheme
      $uri = str_replace(['http://', 'https://'], '', $uri);
      $this_instance = 'Drush Site: ' . $uri;

      // Set New Relic transaction name and parameters if command details are available
      if (isset($command['command']) && isset($command['arguments'])) {
        $drush_command = array_merge([$command['command']], $command['arguments']);
        $command_str = implode(' ', $drush_command);

        // Add custom parameters to New Relic
        newrelic_add_custom_parameter('Drush command', $command_str);
        newrelic_name_transaction($command_str);

        // Indicate that this is a background job
        newrelic_background_job(TRUE);
      }
    }
  }
  else {
    // Non-Drush (web request) context
    if (isset($_SERVER['SERVER_NAME'])) {
      $this_instance = 'Web Site: ' . $_SERVER['SERVER_NAME'];
      // Optionally, indicate this is not a background job
      // newrelic_background_job(FALSE);
    }
  }

  // Apply the New Relic app name if determined
  if ($this_instance) {
    ini_set('newrelic.appname', $this_instance);
    newrelic_set_appname($this_instance);
  }
}
elseif (extension_loaded('newrelic') && empty($all_ini['enable_newrelic_integration'])) {
  // Disable New Relic auto-RUM and ignore transactions if integration is disabled
  newrelic_disable_autorum();
  newrelic_ignore_apdex();
  newrelic_ignore_transaction();
}
