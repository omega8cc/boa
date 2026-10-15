<?php

/**
 * @file
 * Backdrop database cache inside a Valkey outage window.
 *
 * While a window is pending (global-if-valkey.inc) a site runs on its
 * database cache, which nothing kept current while Valkey was up. Entries
 * created up to the second the window began are refused; the site rebuilds
 * them from its database and serves what it writes from then on. Loaded by
 * global-bd-valkey.inc after core/includes/cache.inc, inside a window only.
 */

class BoaWindowBackdropDatabaseCache extends BackdropDatabaseCache {

  protected function prepareItem($cache) {
    $start = function_exists('settings_get') ? (int) settings_get('boa_window_start', 0) : 0;
    if ($start > 0 && isset($cache->created) && $cache->created <= $start) {
      return FALSE;
    }
    return parent::prepareItem($cache);
  }

}
