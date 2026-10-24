<?php # global settings.php

/**
 * A stand-in for Drush's base command class on a locked Drupal 8+ platform.
 *
 * The site-local Drush lock keeps vendor/drush at 0400, which no account
 * user can enter, so the backend's own Drush 8 runs the platform's tasks.
 * A module may still register a Drush command class as a Drupal service
 * (varbase_core does), and a compiler pass of another module may load every
 * service class while the container builds (symfony_mailer 2.x does): the
 * build then stops on Class "Drush\Commands\DrushCommands" not found, and
 * every request of the site answers 500, the relock rebuild included.
 *
 * Outside Drush, and only while the real class cannot be read, that one base
 * class gets an empty stand-in, so the container builds; no request runs a
 * Drush command. Drush 8 defines DRUSH_VERSION and never sees it, and an
 * unlocked platform loads the real class. Drupal 11.4's console command pass
 * also loads the command classes a module keeps in its Command folder, and
 * skips them whether they load or not. A request that loads the class logs
 * it once. Must remain PHP 5.6 compatible (legacy servers).
 */
if (!defined('DRUSH_VERSION')
  && !function_exists('_boa_drush_lock_stand_in')
  && !class_exists('Drush\Commands\DrushCommands', FALSE)) {
  $_boa_dl_root = isset($app_root) ? $app_root : getcwd();
  $_boa_dl_locked = FALSE;
  foreach (array($_boa_dl_root . '/vendor/drush', $_boa_dl_root . '/../vendor/drush') as $_boa_dl_dir) {
    if (is_dir($_boa_dl_dir)) {
      $_boa_dl_locked = !is_readable($_boa_dl_dir . '/drush/src/Commands/DrushCommands.php');
      break;
    }
  }
  if ($_boa_dl_locked) {
    function _boa_drush_lock_stand_in($class) {
      if ($class === 'Drush\Commands\DrushCommands') {
        error_log('BOA: site-local Drush is locked on this platform, so an empty Drush\Commands\DrushCommands stands in for the container build');
        eval('namespace Drush\Commands; abstract class DrushCommands {}');
      }
    }
    spl_autoload_register('_boa_drush_lock_stand_in', TRUE, FALSE);
  }
  unset($_boa_dl_root, $_boa_dl_locked, $_boa_dl_dir);
}
