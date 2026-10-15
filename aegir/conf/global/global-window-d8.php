<?php

/**
 * @file
 * Drupal 8+ database cache inside a Valkey outage window.
 *
 * While a window is pending (global-if-valkey.inc) a site runs on its
 * database cache, and that cache was last written by an earlier window:
 * nothing changed while Valkey was up reached it. Every entry created before
 * the window began is refused, so the site rebuilds what it needs from its
 * database and serves what it writes from then on. Loaded through the class
 * map global-valkey.inc registers, by Drupal 8 and later only (PHP 7.0+).
 */

namespace Drupal\boa_window;

use Drupal\Core\Cache\CacheBackendInterface;
use Drupal\Core\Cache\CacheFactoryInterface;
use Drupal\Core\Site\Settings;

/**
 * Wraps the database cache factory; each bin refuses pre-window entries.
 *
 * Service cache.backend.boa_window: the default backend inside a window, and
 * the redis module's failover service while Valkey is wired. The module asks
 * for it only when its own connection failed, which opens a window of this
 * site's scope; its start is then the threshold.
 */
class WindowBackendFactory implements CacheFactoryInterface {

  /**
   * The database cache factory.
   *
   * @var \Drupal\Core\Cache\CacheFactoryInterface
   */
  protected $inner;

  /**
   * The window's start (microtime), once known.
   *
   * @var float|null
   */
  protected $start;

  /**
   * The bins built so far.
   *
   * @var \Drupal\boa_window\WindowBackend[]
   */
  protected $bins = [];

  public function __construct(CacheFactoryInterface $inner) {
    $this->inner = $inner;
  }

  /**
   * {@inheritdoc}
   */
  public function get($bin) {
    if (!isset($this->bins[$bin])) {
      $this->bins[$bin] = new WindowBackend($this->inner->get($bin), $this->start());
    }
    return $this->bins[$bin];
  }

  /**
   * The threshold: the window global-valkey.inc named, or this site's own.
   */
  protected function start() {
    if (!isset($this->start)) {
      $start = (float) Settings::get('boa_window_start', 0);
      if ($start <= 0 && function_exists('_valkey_window_mark')) {
        $start = (float) _valkey_window_mark((string) Settings::get('boa_window_scope', ''));
      }
      $this->start = $start;
    }
    return $this->start;
  }

}

/**
 * A cache bin that treats entries created before the window as absent.
 *
 * Called with $allow_invalid, the caller gets such an entry marked invalid,
 * as for any other outdated entry.
 */
class WindowBackend implements CacheBackendInterface {

  /**
   * The wrapped bin.
   *
   * @var \Drupal\Core\Cache\CacheBackendInterface
   */
  protected $inner;

  /**
   * The window's start (microtime); 0 refuses nothing.
   *
   * @var float
   */
  protected $start;

  public function __construct(CacheBackendInterface $inner, $start) {
    $this->inner = $inner;
    $this->start = (float) $start;
  }

  /**
   * {@inheritdoc}
   */
  public function get($cid, $allow_invalid = FALSE) {
    $cids = [$cid];
    $items = $this->getMultiple($cids, $allow_invalid);
    return reset($items);
  }

  /**
   * {@inheritdoc}
   */
  public function getMultiple(&$cids, $allow_invalid = FALSE) {
    $items = $this->inner->getMultiple($cids, $allow_invalid);
    if ($this->start > 0) {
      foreach ($items as $cid => $item) {
        if (isset($item->created) && $item->created < $this->start) {
          if ($allow_invalid) {
            $item->valid = FALSE;
          }
          else {
            unset($items[$cid]);
            $cids[] = $cid;
          }
        }
      }
    }
    return $items;
  }

  /**
   * {@inheritdoc}
   */
  public function set($cid, $data, $expire = CacheBackendInterface::CACHE_PERMANENT, array $tags = []) {
    return $this->inner->set($cid, $data, $expire, $tags);
  }

  /**
   * {@inheritdoc}
   */
  public function setMultiple(array $items) {
    return $this->inner->setMultiple($items);
  }

  /**
   * {@inheritdoc}
   */
  public function delete($cid) {
    return $this->inner->delete($cid);
  }

  /**
   * {@inheritdoc}
   */
  public function deleteMultiple(array $cids) {
    return $this->inner->deleteMultiple($cids);
  }

  /**
   * {@inheritdoc}
   */
  public function deleteAll() {
    return $this->inner->deleteAll();
  }

  /**
   * {@inheritdoc}
   */
  public function invalidate($cid) {
    return $this->inner->invalidate($cid);
  }

  /**
   * {@inheritdoc}
   */
  public function invalidateMultiple(array $cids) {
    return $this->inner->invalidateMultiple($cids);
  }

  /**
   * {@inheritdoc}
   */
  public function invalidateAll() {
    return $this->inner->invalidateAll();
  }

  /**
   * {@inheritdoc}
   */
  public function garbageCollection() {
    return $this->inner->garbageCollection();
  }

  /**
   * {@inheritdoc}
   */
  public function removeBin() {
    return $this->inner->removeBin();
  }

}
