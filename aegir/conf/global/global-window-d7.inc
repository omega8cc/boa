<?php

/**
 * @file
 * Drupal 6 and 7 database cache inside a Valkey outage window.
 *
 * While a window is pending (global-if-valkey.inc) a site runs on its
 * database cache, which nothing kept current while Valkey was up. Entries
 * created up to the second the window began are refused; the site rebuilds
 * them from its database and serves what it writes from then on. Loaded by
 * global-valkey.inc inside a window only: after includes/cache.inc on Drupal
 * 7, through cache_backport's cache_backends on Drupal 6. Must remain PHP 5.6
 * compatible.
 */

class BoaWindowDatabaseCache extends DrupalDatabaseCache {

  protected function prepareItem($cache) {
    $start = isset($GLOBALS['conf']['boa_window_start']) ? (int) $GLOBALS['conf']['boa_window_start'] : 0;
    if ($start > 0 && isset($cache->created) && $cache->created <= $start) {
      return FALSE;
    }
    return parent::prepareItem($cache);
  }

}
